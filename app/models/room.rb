class Room < ApplicationRecord
  include Announceable, Restorable, Sortable, Deactivatable

  CannotDeleteOriginalError = Class.new(StandardError)

  has_many :memberships, -> { active } do
    def grant_to(users)
      room = proxy_association.owner
      Membership.upsert_all(
        Array(users).collect { |user| { room_id: room.id, user_id: user.id, involvement: room.default_involvement(user: user), active: true } },
        unique_by: %i[room_id user_id]
      )
      room.threads.find_each { |thread| thread.memberships.grant_to(users) }
    end

    def revoke_from(users)
      room = proxy_association.owner
      user_ids = Array(users).map(&:id)

      room.ensure_visible_members_remain!(excluding: user_ids)

      # Must use the `user_id: ...` condition and not `user: ...` for the hierarchical permissions to work
      Membership.active.where(room_id: room.id, user_id: user_ids).update(active: false)
      room.threads.find_each { |thread| thread.memberships.revoke_from(users) }
    end

    def revise(granted: [], revoked: [])
      transaction do
        grant_to(granted) if granted.present?
        revoke_from(revoked) if revoked.present?
      end
    end
  end

  has_many :users, -> { active }, through: :memberships, class_name: "User"
  has_many :visible_memberships, -> { active.visible }, class_name: "Membership"
  has_many :visible_users, through: :visible_memberships, source: :user, class_name: "User"
  has_many :messages, -> { active }, class_name: "Message"
  has_one :last_message, -> { active.without_events.order(created_at: :desc) }, class_name: "Message"
  has_many :threads, through: :messages, class_name: "Rooms::Thread"
  belongs_to :parent_message, class_name: "Message", optional: true
  has_one :parent_room, through: :parent_message, source: :room, class_name: "Room"

  belongs_to :creator, class_name: "User", default: -> { Current.user }

  # Use before_destroy to clean up ALL records (including inactive) to satisfy FK constraints
  before_destroy :destroy_all_associated_records

  before_validation :set_initial_last_active_at, on: :create

  scope :opens,           -> { where(type: "Rooms::Open") }
  scope :closeds,         -> { where(type: "Rooms::Closed") }
  scope :forums,          -> { where(type: "Rooms::Forum") }
  scope :directs,         -> { where(type: "Rooms::Direct") }
  scope :without_directs, -> { where.not(type: "Rooms::Direct") }
  scope :without_threads, -> { where.not(type: "Rooms::Thread") }

  scope :ordered, -> { order(:sortable_name) }
  scope :matching, ->(query) {
    query.present? ? where("name LIKE ?", "%#{sanitize_sql_like(query)}%") : all
  }

  class << self
    def create_for(attributes, users:)
      transaction do
        create!(attributes).tap do |room|
          room.memberships.grant_to users
        end
      end
    end

    def original
      Rails.cache.fetch([ "rooms", "original", ApplicationRecord.try(:current_tenant) ], skip_nil: true) do
        unscoped.order(:created_at).first
      end
    end
  end

  def receive(message)
    unread_memberships(message)
  end

  # Routing-vocabulary symbols that apply to a message in this room — a subset
  # of `Notification::Routing::ACTIVITY_TYPES`. Subclasses override to encode
  # room-type fan-out so callers don't branch on `room.is_a?(Rooms::Direct)`.
  def applicable_activity_types(_message)
    []
  end

  def involve_user(user, unread: false)
    membership = memberships.create_with(involvement: "mentions").find_or_create_by(user: user)
    membership.update(unread_at: messages.last&.created_at || Time.current) if unread && membership.read?
    membership.ensure_receives_mentions!
  end

  def open?
    is_a?(Rooms::Open)
  end

  def closed?
    is_a?(Rooms::Closed)
  end

  def direct?
    is_a?(Rooms::Direct)
  end

  def one_on_one?
    direct? && memberships.count == 2
  end

  def roommate_to(user)
    return nil unless one_on_one?

    users.without(user).first
  end

  def thread?
    is_a?(Rooms::Thread)
  end

  def forum?
    is_a?(Rooms::Forum)
  end

  def sidebar_room?
    open? || closed? || forum?
  end

  def default_involvement(user: nil)
    "mentions"
  end

  def active_member_count
    Rails.cache.fetch(active_member_count_cache_key, expires_in: 5.minutes) do
      memberships.visible.joins(:user).merge(User.active).count
    end
  end

  def invalidate_member_count_cache
    Rails.cache.delete(active_member_count_cache_key)
  end

  def reactivate
    transaction do
      reactivate_threads
      # rewhere replaces the default `-> { active }` scope on the association,
      # allowing us to find deactivated memberships
      memberships.rewhere(active: false).update_all(active: true)
      Message.where(room_id: id, active: false).update_all(active: true)
      activate!
    end
  end

  def toggle_access!(open:)
    target_class = open ? Rooms::Open : Rooms::Closed
    return self if self.class == target_class

    becomes!(target_class).save!
    Room.find(id)
  end

  def original?
    id == Room.original&.id
  end

  # Deactivates the room and all associated data. Called when an admin deletes
  # a room from the UI. Also deactivates any threads spawned from messages in
  # this room - those threads become inaccessible until the room is reactivated.
  def deactivate
    raise CannotDeleteOriginalError if original?

    transaction do
      deactivate_threads
      memberships.update_all(active: false)
      Message.where(room_id: id).update_all(active: false)
      destroy_notifications_for_messages
      deactivate!
    end
  end

  # Creates a system event message using insert! to bypass all ActiveRecord
  # callbacks (notifications, search indexing, push, counter_cache, etc.).
  # Only the room-level Turbo Stream append is broadcast.
  def post_system_message(event:, body:, actor:)
    now = Time.current
    client_message_id = Random.uuid

    Message.insert!({
      room_id: id,
      event: event,
      creator_id: actor.id,
      client_message_id: client_message_id,
      mentions_everyone: false,
      created_at: now,
      updated_at: now
    })

    message = Message.find_by!(client_message_id: client_message_id)

    ActionText::RichText.insert!({
      record_type: "Message",
      record_id: message.id,
      name: "body",
      body: body,
      created_at: now,
      updated_at: now
    })

    message.broadcast_append_to self, :messages, target: [ self, :messages ],
      partial: "messages/message", locals: { current_room: self, is_unread: true }

    message
  end

  def add_member!(user, actor:)
    memberships.grant_to(user)
    invalidate_member_count_cache
    announce_membership_changes(granted: [ user ], actor: actor)
  end

  def remove_member!(user, actor:)
    memberships.revoke_from(user)
    invalidate_member_count_cache
    announce_membership_changes(revoked: [ user ], actor: actor)
  end

  def accept_join!(user)
    memberships.grant_to(user)
    invalidate_member_count_cache
    post_system_message(event: "member_joined", body: "joined", actor: user)
  end

  def post_welcome_message(user:)
    body = user.bot? ? "has been added as a bot." : "joined the community. Say hello!"

    messages.create!(
      creator: user,
      welcome: true,
      body: body,
      client_message_id: Random.uuid
    )
  end

  def ensure_visible_members_remain!(excluding:)
    return if open? || forum?
    remaining = memberships.visible.where.not(user_id: Array(excluding)).count
    raise Membership::LastVisibleMemberError if remaining <= 0
  end

  def accept_leave!(user)
    memberships.find_by!(user: user).leave!
    post_system_message(event: "member_left", body: "left", actor: user)
  end

  def bot_memberships_for_events(item, event)
    bot_ids = User.active_bots.pluck(:id)
    return [] if bot_ids.empty?

    eligible = memberships.active
      .where(involvement: [ :mentions, :everything ])
      .where(user_id: bot_ids)
      .includes(user: :webhook)

    if direct? || thread?
      eligible.to_a
    elsif item.is_a?(Message) && event == :created
      eligible.to_a.select { |m| item.mentionees.include?(m.user) || item.mentions_everyone? }
    else
      eligible.to_a
    end
  end

  def display_name(for_user: nil)
    if direct?
      # Use Ruby select/map instead of pluck to leverage preloaded users
      users.reject { |u| u == for_user }.map(&:name).to_sentence.presence || for_user&.name
    elsif thread?
      # Forum post-threads carry the post title in `name`; chat threads have no
      # name and fall back to the thread glyph plus their parent room's name.
      name.presence || "🧵 #{parent_message&.room&.name}"
    else
      name
    end
  end

  private
    def destroy_notifications_for_messages
      message_ids = Message.where(room_id: id).pluck(:id)
      return if message_ids.empty?

      Notification.delete_all_and_broadcast(Notification.where(message_id: message_ids))
    end

    def active_member_count_cache_key
      tenant_prefix = ApplicationRecord.current_tenant if Sabha.saas?
      [ tenant_prefix, "room", id, "active_member_count" ].compact.join(":")
    end

    def set_initial_last_active_at
      self.last_active_at = Time.current
    end

    def unread_memberships(message)
      # Mark read users as unread
      memberships.visible.disconnected.read.where.not(user: message.creator)
        .update_all(unread_at: message.created_at, updated_at: Time.current)

      # Broadcast to ALL disconnected users (not just newly unread)
      # Already-unread users need updated roomSize/roomUpdatedAt for sidebar ordering
      broadcast_unread_to_disconnected_users(message)
    end

    def broadcast_unread_to_disconnected_users(message)
      users = memberships.visible.disconnected.where.not(user: message.creator).includes(:user).map(&:user)
      return if users.empty?

      payload = {
        roomId: id,
        roomSize: messages_count,
        roomUpdatedAt: last_active_at.iso8601,
        forceUnread: true
      }
      users.each do |user|
        UserUnreadRoomsChannel.broadcast_to(user, payload)
      end
    end

    def deactivate_threads
      message_ids = Message.where(room_id: id).pluck(:id)
      # Only cascade-deactivate posts that are still active. Posts already
      # deleted on their own keep their non-cascade marker, so reactivation
      # leaves them deleted (R15).
      Rooms::Thread.active.where(parent_message_id: message_ids)
        .find_each { |thread| thread.deactivate(cascade: true) }
    end

    def reactivate_threads
      message_ids = Message.where(room_id: id).pluck(:id)
      # Restore only posts this room's cascade deactivated — never ones deleted
      # individually beforehand (R15).
      Rooms::Thread.where(parent_message_id: message_ids, active: false, cascade_deactivated: true)
        .find_each(&:reactivate)
    end

    # Clean up associated records explicitly because the cascade has to walk
    # parent_message → thread → messages → memberships in a specific order to
    # satisfy FK constraints.
    def destroy_all_associated_records
      message_ids = Message.where(room_id: id).pluck(:id)
      post_ids = Rooms::Thread.where(parent_message_id: message_ids).pluck(:id)

      # Taggings reference posts (room_id) and tags (tag_id), and tags reference
      # this forum (room_id) — all RESTRICT FKs, so clear them before the rows
      # they point at. No-ops for non-forum rooms, which own no tags/taggings.
      Tagging.where(room_id: post_ids).delete_all if post_ids.any?
      forum_tag_ids = Tag.where(room_id: id).pluck(:id)
      if forum_tag_ids.any?
        Tagging.where(tag_id: forum_tag_ids).delete_all
        Tag.where(id: forum_tag_ids).delete_all
      end

      # First, destroy any thread rooms that were created from messages in this room
      # (threads have parent_message_id pointing to messages in this room)
      Rooms::Thread.where(parent_message_id: message_ids).find_each(&:destroy)

      # Then delete messages (they have FKs to boosts, bookmarks, notifications)
      Message.where(room_id: id).find_each(&:destroy)

      # Finally delete memberships
      Membership.where(room_id: id).delete_all
    end
end
