class Room < ApplicationRecord
  include Deactivatable

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

  before_save :set_sortable_name
  after_save_commit :broadcast_updates, if: :saved_change_to_sortable_name?

  scope :opens,           -> { where(type: "Rooms::Open") }
  scope :closeds,         -> { where(type: "Rooms::Closed") }
  scope :directs,         -> { where(type: "Rooms::Direct") }
  scope :without_directs, -> { where.not(type: "Rooms::Direct") }
  scope :without_threads, -> { where.not(type: "Rooms::Thread") }

  scope :ordered, -> { order(:sortable_name) }

  after_update_commit :broadcast_reactivation_if_restored
  after_create_commit :announce_creation

  class << self
    def create_for(attributes, users:)
      transaction do
        create!(attributes).tap do |room|
          room.memberships.grant_to users
        end
      end
    end

    def original
      unscoped.order(:created_at).first
    end
  end

  def as_bot_json(bot_key:, url_helper:)
    { id: id, name: name, type: type.demodulize, messages_url: url_helper.call(self, bot_key) }
  end

  def receive(message)
    unread_memberships(message)
    push_later(message)
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

  def sidebar_room?
    open? || closed?
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
      Message.unscoped.where(room_id: id, active: false).update_all(active: true)
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
      Message.unscoped.where(room_id: id).update_all(active: false)
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
    messages.create!(
      creator: user,
      welcome: true,
      body: "joined the community. Say hello!",
      client_message_id: Random.uuid
    )
  end

  def ensure_visible_members_remain!(excluding:)
    return if open?
    remaining = memberships.visible.where.not(user_id: Array(excluding)).count
    raise Membership::LastVisibleMemberError if remaining <= 0
  end

  def accept_leave!(user)
    memberships.find_by!(user: user).leave!
    post_system_message(event: "member_left", body: "left", actor: user)
  end

  def announce_membership_changes(granted: [], revoked: [], actor:)
    if granted.present?
      post_system_message(event: "member_joined", body: membership_change_text("added", granted), actor: actor)
    end
    if revoked.present?
      post_system_message(event: "member_left", body: membership_change_text("removed", revoked), actor: actor)
    end
  end

  def announce_rename(old_name, actor:)
    post_system_message(event: "room_renamed", body: "renamed the room from #{old_name} to #{name}", actor: actor)
  end

  def bot_memberships_for_webhook(message, event)
    bot_ids_with_webhook = User.active_bots.joins(:webhook).pluck(:id)
    return [] if bot_ids_with_webhook.empty?

    eligible = memberships.active
      .where.not(involvement: [ :invisible, :nothing ])
      .where(user_id: bot_ids_with_webhook)
      .includes(user: :webhook)

    if direct?
      eligible.to_a
    elsif message.is_a?(Message) && event == :created
      eligible.to_a.select { |m| m.involved_in_everything? || message.mentionees.include?(m.user) || message.mentions_everyone? }
    else
      eligible.where(involvement: :everything).to_a
    end
  end

  def display_name(for_user: nil)
    if direct?
      # Use Ruby select/map instead of pluck to leverage preloaded users
      users.reject { |u| u == for_user }.map(&:name).to_sentence.presence || for_user&.name
    elsif thread?
      "🧵 #{parent_message&.room&.name}"
    else
      name
    end
  end

  private
    def destroy_notifications_for_messages
      message_ids = Message.unscoped.where(room_id: id).pluck(:id)
      return if message_ids.empty?

      Notification.delete_all_and_broadcast(Notification.where(message_id: message_ids))
    end

    def active_member_count_cache_key
      tenant_prefix = ApplicationRecord.current_tenant if Sabha.saas?
      [ tenant_prefix, "room", id, "active_member_count" ].compact.join(":")
    end

    def membership_change_text(verb, users)
      if users.size <= 2
        "#{verb} #{users.map(&:name).to_sentence}"
      else
        "#{verb} #{users.size} members"
      end
    end

    def set_initial_last_active_at
      self.last_active_at = Time.current
    end

    def broadcast_reactivation_if_restored
      broadcast_reactivation if saved_change_to_attribute?(:active) && active?
    end

    def announce_creation
      return if direct? || thread?
      return unless User.active.where.not(id: creator_id).exists? # No audience on fresh setup
      post_system_message(event: "room_created", body: "created the room", actor: creator)
    end

    def set_sortable_name
      self.sortable_name = name.to_s.gsub(/[[:^ascii:]\p{So}]/, "").strip.downcase
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

    def push_later(message)
      Room::PushMessageJob.perform_later(self, message)
    end

    def broadcast_updates
      RoomListChannel.broadcast_to(Account.sole, { roomId: id, sortableName: sortable_name })
    rescue ActiveRecord::RecordNotFound
      # No account yet (e.g., during setup or seed)
    end

    def broadcast_reactivation
      return unless sidebar_room?

      memberships.visible.includes(:user).find_each do |membership|
        list_name = membership.sidebar_list_name
        Turbo::StreamsChannel.broadcast_append_to(
          membership.user, :rooms,
          target: list_name,
          partial: "users/sidebars/rooms/shared",
          locals: { list_name:, membership: membership, room: self },
          attributes: { maintain_scroll: true }
        )
      end
    end

    def deactivate_threads
      message_ids = Message.unscoped.where(room_id: id).pluck(:id)
      Rooms::Thread.where(parent_message_id: message_ids).find_each(&:deactivate)
    end

    def reactivate_threads
      message_ids = Message.unscoped.where(room_id: id).pluck(:id)
      Rooms::Thread.unscoped.where(parent_message_id: message_ids, active: false).find_each(&:reactivate)
    end

    # Clean up ALL associated records (including inactive ones) to satisfy FK constraints.
    #
    # Why this exists instead of `dependent: :destroy`:
    # The `messages` association has `-> { active }` scope for soft deletion, so Rails'
    # `dependent: :destroy` only finds active records. We need to delete inactive
    # records too, hence the explicit unscoped queries.
    def destroy_all_associated_records
      # First, destroy any thread rooms that were created from messages in this room
      # (threads have parent_message_id pointing to messages in this room)
      message_ids = Message.unscoped.where(room_id: id).pluck(:id)
      Rooms::Thread.unscoped.where(parent_message_id: message_ids).find_each(&:destroy)

      # Then delete messages (they have FKs to boosts, bookmarks, notifications)
      Message.unscoped.where(room_id: id).find_each(&:destroy)

      # Finally delete memberships
      Membership.unscoped.where(room_id: id).delete_all
    end
end
