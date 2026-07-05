class Room < ApplicationRecord
  include Announceable, Restorable, Sortable, Deactivatable

  CannotDeleteOriginalError = Class.new(StandardError)

  # The STI types of nested sub-rooms — chat threads and forum posts. The single
  # source for the type list; both the sub_rooms and without_threads scopes read it.
  SUB_ROOM_TYPES = %w[ Rooms::Thread Rooms::Post ].freeze

  has_many :memberships, -> { active } do
    def grant_to(users)
      room = proxy_association.owner
      Membership.upsert_all(
        Array(users).collect { |user| { room_id: room.id, user_id: user.id, involvement: room.default_involvement(user: user), active: true } },
        unique_by: %i[room_id user_id]
      )
    end

    def revoke_from(users)
      room = proxy_association.owner
      user_ids = Array(users).map(&:id)

      room.ensure_visible_members_remain!(excluding: user_ids)

      # Must use the `user_id: ...` condition and not `user: ...` for the hierarchical permissions to work
      Membership.active.where(room_id: room.id, user_id: user_ids).update(active: false)
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
  # Denormalized direct FK to the room a thread was spawned in (the forum, for a
  # forum post) — the same shape messages have via room_id. Set from
  # parent_message.room on create; lets the gallery query threads without joining
  # through messages. Assigned in Rooms::Thread#assign_parent_room.
  belongs_to :parent_room, class_name: "Room", optional: true

  belongs_to :creator, class_name: "User", default: -> { Current.user }

  # Use before_destroy to clean up ALL records (including inactive) to satisfy FK constraints
  before_destroy :destroy_all_associated_records

  before_validation :set_initial_last_active_at, on: :create

  scope :opens,           -> { where(type: "Rooms::Open") }
  scope :closeds,         -> { where(type: "Rooms::Closed") }
  scope :forums,          -> { where(type: "Rooms::Forum") }
  scope :directs,         -> { where(type: "Rooms::Direct") }
  scope :without_directs, -> { where.not(type: "Rooms::Direct") }
  # Excludes nested sub-rooms — chat threads and forum posts — from top-level
  # room listings and the sidebar. (Named for threads historically; it now also
  # covers Rooms::Post, which is likewise a sub-room, not a sidebar room.)
  scope :without_threads, -> { where.not(type: SUB_ROOM_TYPES) }
  # Nested sub-rooms — chat threads and forum posts; the class-level complement
  # of #sub_room?.
  scope :sub_rooms, -> { where(type: SUB_ROOM_TYPES) }

  # Rooms a user can discover and join from Browse: open rooms and forums they
  # aren't already in. Called on Room for both; on Rooms::Open (bots API) STI
  # narrows it back to open rooms only.
  scope :browsable_by, ->(user) {
    active.where(type: %w[ Rooms::Open Rooms::Forum ])
          .where.not(id: user.memberships.visible.select(:room_id))
  }

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

  def post?
    is_a?(Rooms::Post)
  end

  def sidebar_room?
    open? || closed? || forum?
  end

  # Chat threads and forum posts are nested sub-rooms — they derive access from a
  # parent and never stand on their own in the sidebar.
  def sub_room?
    thread? || post?
  end

  # Access to a room derives from active membership. Sub-rooms (chat threads and
  # forum posts) override this to delegate to their parent, so a parent member
  # can open them without a per-sub-room membership row of their own.
  def viewable_by?(user)
    user.present? && memberships.active.exists?(user_id: user.id)
  end

  def default_involvement(user: nil)
    "mentions"
  end

  # The users who can be @mentioned here. Rooms::Post overrides this — its access
  # derives from its forum, so a post mentions the forum's members, not the
  # handful who happen to have followed it.
  def mentionable_users
    users
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
    # Forums render a gallery of posts, not a message stream — a system event
    # message here is an orphaned write nothing ever displays. Skip it for every
    # event type (join, leave, rename, member changes).
    return if forum?

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
    clean_up_thread_follows_later(user)
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
    clean_up_thread_follows_later(user)
    post_system_message(event: "member_left", body: "left", actor: user)
  end

  # Silence one member's chat-thread follows so reply notifications stop for a
  # room they left — their per-thread memberships go invisible. Scoped to that
  # member, never touches other members. Runs from ThreadFollowCleanupJob.
  # Mirrors Rooms::Forum#silence_post_follows_for for a forum's posts.
  def silence_thread_follows_for(user)
    thread_ids = Rooms::Thread.where(parent_room_id: id).select(:id)
    Membership.active.where(user_id: user.id, room_id: thread_ids)
              .where.not(involvement: "invisible")
              .update_all(involvement: "invisible")
  end

  def bot_memberships_for_events(item, event)
    bot_ids = User.active_bots.pluck(:id)
    return [] if bot_ids.empty?

    eligible = memberships.active
      .where(involvement: [ :mentions, :everything ])
      .where(user_id: bot_ids)
      .includes(user: :webhook)

    if direct? || thread? || post?
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
      # A chat thread shows its given name if it was renamed, else the thread
      # glyph plus the name of the room it was spawned in.
      name.presence || "🧵 #{parent_message&.room&.name}"
    else
      name
    end
  end

  private
    # Only Open and Closed rooms spawn chat threads, so only they need the
    # follow-silencing sweep on leave. Forums run their own post-follow cleanup,
    # and directs/sub-rooms have no threads to silence.
    def clean_up_thread_follows_later(user)
      return unless open? || closed?
      ThreadFollowCleanupJob.perform_later(room: self, user: user)
    end

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

    # Cascade-deactivate this room's nested sub-rooms: chat threads (spawned off
    # its messages) and, for a forum, its posts (owned via parent_room_id). Only
    # cascade-deactivate still-active ones; sub-rooms already deleted on their own
    # keep their non-cascade marker, so reactivation leaves them deleted.
    def deactivate_threads
      message_ids = Message.where(room_id: id).pluck(:id)
      Rooms::Thread.active.where(parent_message_id: message_ids)
        .find_each { |thread| thread.deactivate(cascade: true) }

      if forum?
        Rooms::Post.active.where(parent_room_id: id)
          .find_each { |post| post.deactivate(cascade: true) }
      end
    end

    def reactivate_threads
      message_ids = Message.where(room_id: id).pluck(:id)
      # Restore only sub-rooms this room's cascade deactivated — never ones
      # deleted individually beforehand.
      Rooms::Thread.where(parent_message_id: message_ids, active: false, cascade_deactivated: true)
        .find_each(&:reactivate)

      if forum?
        Rooms::Post.where(parent_room_id: id, active: false, cascade_deactivated: true)
          .find_each(&:reactivate)
      end
    end

    # Clean up associated records explicitly because the cascade has to walk
    # nested sub-rooms → messages → memberships in a specific order to satisfy FK
    # constraints.
    def destroy_all_associated_records
      message_ids = Message.where(room_id: id).pluck(:id)

      # First, destroy nested sub-rooms: chat threads spawned from this room's
      # messages, and (for a forum) its posts owned via parent_room_id. Each
      # cleans up its own messages, memberships, and solution on destroy.
      Rooms::Thread.where(parent_message_id: message_ids).find_each(&:destroy)
      Rooms::Post.where(parent_room_id: id).find_each(&:destroy) if forum?

      # Then delete messages (they have FKs to boosts, bookmarks, notifications)
      Message.where(room_id: id).find_each(&:destroy)

      # Finally delete memberships
      Membership.where(room_id: id).delete_all
    end
end
