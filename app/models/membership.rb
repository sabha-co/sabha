class Membership < ApplicationRecord
  include Cacheable, Connectable, Involvable, Starrable, Deactivatable, Notifiable

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

  scope :read,    -> { where(unread_at: nil) }
  scope :unread,  -> { where.not(unread_at: nil) }

  def read_until(time)
    return if read? || time < unread_at

    new_unread_at = room.messages.without_events.ordered.where("created_at > ?", time).first&.created_at
    update!(unread_at: new_unread_at, unread_notifications_count: count_unread_notifications_from(new_unread_at))
    broadcast_read if read?
  end

  def mark_unread_at(message)
    update!(unread_at: message.created_at, unread_notifications_count: count_unread_notifications_from(message.created_at))
    broadcast_unread
  end

  def read
    update!(unread_at: nil, unread_notifications_count: 0)
    broadcast_read
  end

  def clear_unread_notifications_until(time)
    update!(unread_notifications_count: count_unread_notifications_after(time))
  end

  def read?
    unread_at.blank?
  end

  def unread?
    unread_at.present?
  end

  def has_unread_notifications?
    unread_notifications_count > 0
  end

  def sidebar_list_name
    starred? ? :starred_rooms : :shared_rooms
  end

  def receives_mentions?
    involved_in_mentions? || involved_in_everything?
  end

  # Per-room involvement after applying the global mode override. Predicates
  # ask this only — they don't read mode and involvement independently.
  # Per-room :everything wins (opt-in beats global mute); otherwise global
  # :nothing applies; else fall back to per-room involvement.
  def effective_involvement
    return :everything if involved_in_everything?
    return :nothing if user.try(:notification_settings)&.mode == "nothing"
    involvement.to_sym
  end

  def ensure_receives_mentions!
    update(involvement: :mentions) unless receives_mentions?
  end

  # Recompute the count of notification-worthy unread messages from a given anchor.
  # Returns 0 when the anchor is nil (membership is read).
  def count_unread_notifications_from(anchor_time)
    return 0 if anchor_time.nil?

    base = room.messages.where("created_at >= ?", anchor_time)

    if room.direct?
      base.count
    else
      base.where(
        "messages.mentions_everyone = ? OR EXISTS (" \
          "SELECT 1 FROM notifications WHERE notifications.message_id = messages.id " \
          "AND notifications.user_id = ? AND notifications.activity_type = 'mention')",
        true, user_id
      ).count
    end
  end

  private
    def broadcast_read
      ReadRoomsChannel.broadcast_to(user, { room_id: room_id })
    end

    def broadcast_unread
      UserUnreadRoomsChannel.broadcast_to(user, unread_payload)
      UnreadNotificationsChannel.broadcast_to(user, notification_payload) if has_unread_notifications?
    end

    def count_unread_notifications_after(time)
      return 0 if unread_at.nil?

      Notification.joins(:message)
        .where(user_id: user_id, activity_type: "mention", messages: { room_id: room_id })
        .where("messages.created_at >= ?", unread_at)
        .where("notifications.created_at > ?", time)
        .count
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
