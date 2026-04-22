class Membership < ApplicationRecord
  include Connectable, Deactivatable

  class LastVisibleMemberError < StandardError; end

  def leave!
    with_lock do
      room.ensure_visible_members_remain!(excluding: user_id)
      update!(involvement: :invisible)
    end
  end

  belongs_to :room
  belongs_to :user

  has_many :unread_notifications, ->(membership) {
    scope = since(membership.unread_at || Time.current)

    if membership.room.direct?
      scope
    else
      scope.where(
        "EXISTS (SELECT 1 FROM notifications WHERE notifications.message_id = messages.id
          AND notifications.user_id = ? AND notifications.activity_type = 'mention')
         OR messages.mentions_everyone = ?",
        membership.user_id, true
      ).distinct
    end
  }, through: :room, source: :messages

  scope :with_has_unread_notifications, -> {
    select(
      "memberships.*",

      <<~SQL.squish
      (
        SELECT COUNT(DISTINCT messages.id)
        FROM messages
        WHERE messages.room_id = memberships.room_id
          AND messages.created_at >= COALESCE(
            memberships.unread_at,
            '#{Time.current.utc.iso8601}'
          )
          AND (
            EXISTS (
              SELECT 1
              FROM rooms
              WHERE rooms.id = memberships.room_id
                AND rooms.type = 'Rooms::Direct'
            )
            OR EXISTS (
              SELECT 1
              FROM notifications
              WHERE notifications.message_id = messages.id
                AND notifications.user_id = memberships.user_id
                AND notifications.activity_type = 'mention'
            )
            OR messages.mentions_everyone = true
          )
      ) AS preloaded_unread_notifications_count
    SQL
    )
  }

  after_update_commit :reset_user_connections_if_deactivated
  after_destroy_commit :reset_user_connections
  after_commit :invalidate_room_member_count_cache

  enum :involvement, %w[ invisible nothing mentions everything ].index_by(&:itself), prefix: :involved_in

  validate :starred_only_for_shared_visible_rooms, if: :starred?
  before_validation :unstar_if_invisible

  after_update :broadcast_involvement, if: :saved_change_to_involvement?
  after_update_commit :broadcast_star_change, if: :saved_change_to_starred?

  scope :with_ordered_room, -> { includes(:room).joins(:room).order("rooms.sortable_name") }
  scope :with_room_by_activity, -> { includes(:room).joins(:room).order("rooms.messages_count DESC") }
  scope :with_room_by_last_active_newest_first, -> { includes(:room).joins(:room).order("rooms.last_active_at DESC") }
  scope :with_room_chronologically, -> { includes(:room).joins(:room).order("rooms.created_at") }
  scope :with_room_by_sort_preference, ->(preference) {
    case preference
    when "alphabetical"
      with_ordered_room
    when "most_active"
      with_room_by_activity
    else
      with_room_by_last_active_newest_first
    end
  }
  scope :shared, -> { joins(:room).where(rooms: { type: %w[Rooms::Open Rooms::Closed] }) }
  scope :direct_rooms, -> { joins(:room).where(rooms: { type: "Rooms::Direct" }) }
  scope :without_direct_rooms, -> { joins(:room).where.not(rooms: { type: "Rooms::Direct" }) }
  scope :without_thread_rooms, -> { joins(:room).where.not(rooms: { type: "Rooms::Thread" }) }
  scope :active_rooms, -> { joins(:room).where(rooms: { active: true }) }
  scope :with_messages, -> { joins(:room).where("rooms.messages_count > 0") }
  # Memberships that have unread messages OR whose room was updated recently.
  # Used to filter direct messages in the sidebar to only show recent conversations.
  scope :recently_active_or_unread, ->(since: 7.days.ago) {
    joins(:room).where("memberships.unread_at IS NOT NULL OR rooms.updated_at > ?", since)
  }

  scope :starred, -> { where(starred: true) }
  scope :unstarred, -> { where(starred: false) }
  scope :notifications_on, -> { where(involvement: :everything) }
  scope :visible, -> { where.not(involvement: :invisible) }
  scope :read,  -> { where(unread_at: nil) }
  scope :unread,  -> { where.not(unread_at: nil) }

  def read_until(time)
    return if read? || time < unread_at

    update!(unread_at: room.messages.without_events.ordered.where("created_at > ?", time).first&.created_at)
    broadcast_read if read?
  end

  def mark_unread_at(message)
    update!(unread_at: message.created_at)
    broadcast_unread
  end

  def read
    update!(unread_at: nil)
    broadcast_read
  end

  def read?
    unread_at.blank?
  end

  def unread?
    unread_at.present?
  end

  def has_unread_notifications?
    if attributes.has_key?("preloaded_unread_notifications_count")
      self[:preloaded_unread_notifications_count].to_i > 0
    else
      unread? && unread_notifications.any?
    end
  end

  def unread_notifications_count
    if attributes.has_key?("preloaded_unread_notifications_count")
      self[:preloaded_unread_notifications_count].to_i
    else
      unread? ? unread_notifications.count : 0
    end
  end

  def sidebar_list_name
    starred? ? :starred_rooms : :shared_rooms
  end

  def receives_mentions?
    involved_in_mentions? || involved_in_everything?
  end

  def ensure_receives_mentions!
    update(involvement: :mentions) unless receives_mentions?
  end

  private
    def starred_only_for_shared_visible_rooms
      if room.direct? || room.thread?
        errors.add(:starred, "is not allowed for direct or thread rooms")
      end
    end

    def unstar_if_invisible
      self.starred = false if involved_in_invisible? && starred?
    end

    def reset_user_connections_if_deactivated
      user.reset_remote_connections if deactivated?
    end

    def reset_user_connections
      user.reset_remote_connections
    end

    def invalidate_room_member_count_cache
      room&.invalidate_member_count_cache

      # Also invalidate the previous room's cache if room_id changed
      if saved_change_to_room_id? && room_id_before_last_save
        Room.find_by(id: room_id_before_last_save)&.invalidate_member_count_cache
      end
    end

    def broadcast_read
      ReadRoomsChannel.broadcast_to(user, { room_id: room_id })
    end

    def broadcast_unread
      UserUnreadRoomsChannel.broadcast_to(user, unread_payload)
      UnreadNotificationsChannel.broadcast_to(user, notification_payload) if has_unread_notifications?
    end

    def broadcast_involvement
      UserInvolvementsChannel.broadcast_to(user, { roomId: room_id, involvement: involvement })
    end

    def broadcast_star_change
      return if involved_in_invisible? || room.direct? || room.thread?

      old_list = starred_before_last_save ? :starred_rooms : :shared_rooms

      Turbo::StreamsChannel.broadcast_remove_to(
        user, :rooms,
        target: [ room, "#{old_list}_list_node" ]
      )

      Turbo::StreamsChannel.broadcast_append_to(
        user, :rooms,
        target: sidebar_list_name,
        partial: "users/sidebars/rooms/shared",
        locals: { list_name: sidebar_list_name, membership: self },
        attributes: { maintain_scroll: true }
      )
    end

    def unread_payload
      {
        roomId: room.id,
        roomSize: room.messages_count,
        roomUpdatedAt: room.last_active_at.iso8601,
        forceUnread: true
      }
    end

    def notification_payload
      { roomId: room.id }
    end
end
