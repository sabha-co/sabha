class User < ApplicationRecord
  DEFAULT_NAME = "New Member"
  MINIMUM_PASSWORD_LENGTH = 8

  has_subscriptions
  after_create :subscribe_to_emails, unless: -> { Campfire.saas? }  # Mailkick deferred to v2 for SaaS

  include Avatar, Bannable, Bot, DicebearAvatar, Mentionable, Role, Transferable, Preferences

  # SaaS mode: Link to GlobalIdentity via WorkspaceMembership
  # In single-tenant mode, workspace_membership_id is nil
  belongs_to :workspace_membership, optional: true, class_name: "WorkspaceMembership"

  # Access GlobalIdentity through WorkspaceMembership (SaaS mode)
  def global_identity
    return nil unless Campfire.saas?
    workspace_membership&.global_identity
  end

  # User status enum (replaces active boolean + suspended_at)
  enum :status, %i[active deactivated banned], default: :active

  has_many :memberships, -> { active }, class_name: "Membership"
  has_many :rooms, -> { active }, through: :memberships, source: :room

  has_many :bookmarks, -> { active }, class_name: "Bookmark"
  has_many :bookmarked_messages, -> { order("bookmarks.created_at DESC") }, through: :bookmarks, source: :message
  has_many :reachable_messages, through: :rooms, source: :messages
  has_many :messages, -> { active }, foreign_key: :creator_id, class_name: "Message"

  has_many :mentions, dependent: :delete_all
  has_many :join_codes, class_name: "Account::JoinCode", dependent: :destroy

  def active_invite_link
    join_codes.active.first
  end

  def regenerate_invite_link
    join_codes.destroy_all
    join_codes.create!
  end

  # Use before_destroy to clean up ALL records (including inactive) to satisfy FK constraints
  before_destroy :destroy_all_associated_records

  def mentioning_messages
    Message.active
      .where(room_id: room_ids)
      .left_joins(:mentions, :room)
      .where("mentions.user_id = ? OR messages.mentions_everyone = ? OR rooms.type = ?", id, true, "Rooms::Direct")
      .distinct
  end

  # Marks only rooms with unread activity (@mentions) as read.
  # DMs are handled separately by mark_direct_messages_as_read.
  # Only marks as read if there were no non-mention messages in the window
  # (avoids accidentally marking unread messages as read when user only viewed activity)
  def mark_activity_as_read(loaded_at)
    activity_until = freshness_checked_time(loaded_at)

    memberships.unread.with_has_unread_notifications.each do |m|
      next unless m.has_unread_notifications?
      next if m.room.is_a?(Rooms::Direct)  # Skip DMs - handled separately

      non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, activity_until)
      m.read_until(activity_until) if non_mentions.none?
    end
  end

  # Marks all direct message rooms as read up to the loaded timestamp.
  def mark_direct_messages_as_read(loaded_at)
    dms_until = freshness_checked_time(loaded_at)

    memberships.unread.direct_rooms.each do |m|
      m.read_until(dms_until)
    end
  end

  # Marks inbox as read up to the timestamps when messages were last loaded.
  # Uses stale detection: if timestamp is > 1 hour old, uses current time instead
  # (user likely left the page open without interacting).
  #
  # For activity: DMs are always marked as read. For other rooms, only marks as read
  # if the room had no non-mention messages in the window (avoids accidentally marking
  # unread messages as read when user only viewed activity)
  def mark_inbox_as_read(messages_loaded_at:, notifications_loaded_at:, activity_loaded_at:)
    messages_until = freshness_checked_time(messages_loaded_at)
    notifications_until = freshness_checked_time(notifications_loaded_at)
    activity_until = freshness_checked_time(activity_loaded_at)

    # Mark all visible rooms as read up to when messages were loaded
    memberships.unread.each { |m| m.read_until(messages_until) }

    # Mark notification rooms as read up to when notifications were loaded
    memberships.notifications_on.unread.each { |m| m.read_until(notifications_until) }

    # Mark activity rooms as read: DMs always, others only if no non-mention messages
    memberships.unread.each do |m|
      if m.room.is_a?(Rooms::Direct)
        m.read_until(activity_until)
      else
        non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, activity_until)
        m.read_until(activity_until) if non_mentions.none?
      end
    end
  end

  has_many :push_subscriptions, class_name: "Push::Subscription", dependent: :delete_all

  has_many :boosts, -> { active }, foreign_key: :booster_id, class_name: "Boost"
  has_many :searches, dependent: :delete_all

  has_many :sessions, dependent: :destroy
  has_many :auth_tokens, dependent: :destroy
  has_many :bans, dependent: :destroy

  belongs_to :badge, optional: true

  has_many :blocks_given, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocked_users, through: :blocks_given, source: :blocked

  has_many :blocks_received, class_name: "Block", foreign_key: :blocked_id, dependent: :destroy
  has_many :blocked_by_users, through: :blocks_received, source: :blocker

  validates :email_address, presence: true, if: :person?
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email_address.present? }
  validates :unconfirmed_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }
  normalizes :unconfirmed_email, with: ->(email) { email&.strip&.downcase }

  scope :without_default_names, -> { where.not(name: DEFAULT_NAME) }
  scope :verified, -> { where.not(verified_at: nil) }
  scope :unverified, -> { where(verified_at: nil) }

  has_secure_password validations: false

  generates_token_for :email_verification, expires_in: 24.hours
  generates_token_for :email_change, expires_in: 24.hours
  generates_token_for :password_reset, expires_in: 1.hour

  after_update :send_email_change_notification, if: :saved_change_to_email_address?

  before_validation :set_default_name
  before_validation :normalize_social_urls
  before_save :transliterate_name, if: :name_changed?
  after_create_commit :grant_membership_to_open_rooms

  scope :ordered, -> { order(arel_table[:role].desc, arel_table[:name].lower) }
  scope :recent_posters_first, ->(room_id = nil) do
    messages_table = Message.active.arel_table
    users_table = active.arel_table

    left_join_condition = messages_table[:creator_id].eq(users_table[:id])
    left_join_condition = left_join_condition.and(messages_table[:room_id].eq(room_id)) if room_id.present?

    left_join = users_table.join(messages_table, Arel::Nodes::OuterJoin).on(left_join_condition)

    joins(left_join.join_sources)
      .group(users_table[:id])
      .order(messages_table[:created_at].maximum.desc)
  end
  scope :by_first_name, ->(first_name) { where("CASE WHEN instr(name, ' ') > 0 THEN substr(name, 1, instr(name, ' ')-1) ELSE name END = ?", first_name.to_s.strip) }
  scope :filtered_by, ->(query) {
    return all unless query.present?

    pattern = "%#{sanitize_sql_like(query)}%"
    where("name LIKE :q OR ascii_name LIKE :q OR twitter_username LIKE :q OR linkedin_username LIKE :q", q: pattern)
  }


  def ever_authenticated?
    last_authenticated_at.present?
  end

  def initials
    name.scan(/\b\w/).join
  end

  def title
    [ name, bio ].compact_blank.join(" – ")
  end

  def has_social_links?
    twitter_url.present? || linkedin_url.present? || personal_url.present?
  end

  def reactivate
    transaction do
      # rewhere replaces the default `-> { active }` scope on the association,
      # allowing us to find deactivated memberships
      memberships.rewhere(active: false).without_direct_rooms.update!(active: true)
      update! status: :active
      reset_remote_connections
    end
  end

  def deactivate
    transaction do
      revoke_access
      searches.delete_all
      update! status: :deactivated
    end
  end

  def revoke_access
    close_remote_connections
    memberships.without_direct_rooms.update!(active: false)
    push_subscriptions.delete_all
    sessions.delete_all
    auth_tokens.delete_all
  end

  def reset_remote_connections
    close_remote_connections reconnect: true
  end

  def member_of?(room)
    Membership.active.visible.exists?(room_id: room.id, user_id: id)
  end

  def default_name?
    name == DEFAULT_NAME
  end

  def editable_name
    default_name? ? "" : name
  end

  def joined_at
    created_at
  end

  def total_message_count
    Message.active
           .joins(:room)
           .where(creator_id: id)
           .where("rooms.type != ?", "Rooms::Direct")
           .count
  end

  def recalculate_streak!(excluding_message: nil)
    # Skip if user already posted today (excluding the message that triggered this callback)
    return if posted_on?(Date.current, excluding: excluding_message)

    new_streak = posted_on?(Date.yesterday) ? current_streak + 1 : 1
    update_column(:current_streak, new_streak)
  end

  def posted_on?(date, excluding: nil)
    scope = messages.joins(:room)
                    .joins("LEFT JOIN messages AS parent_messages ON rooms.parent_message_id = parent_messages.id")
                    .joins("LEFT JOIN rooms AS parent_rooms ON parent_messages.room_id = parent_rooms.id")
                    .where.not(rooms: { type: "Rooms::Direct" })
                    .where("parent_rooms.type IS NULL OR parent_rooms.type != ?", "Rooms::Direct")
                    .where("DATE(messages.created_at) = ?", date)
    scope = scope.where.not(id: excluding.id) if excluding
    scope.exists?
  end

  def subscribed_to_emails?
    subscribed?("notifications")
  end

  def subscribe_to_emails
    subscribe("notifications")
  end

  def unsubscribe_from_emails
    unsubscribe("notifications")
  end

  def toggle_email_subscription
    subscribed_to_emails? ? unsubscribe_from_emails : subscribe_to_emails
  end

  def blocked_in?(room)
    return false unless room.one_on_one?

    !can_ping?(room.roommate_to(self))
  end

  def can_ping?(other_user)
    !blocked?(other_user) && !blocked_by?(other_user)
  end

  def can_direct_message?(other_user)
    other_user&.active? &&
      can_ping?(other_user) &&
      can_create_direct_messages?
  end

  def blocked?(other_user)
    blocked_users.exists?(other_user&.id)
  end

  def blocked_by?(other_user)
    blocked_by_users.exists?(other_user&.id)
  end

  def block!(other_user)
    blocks_given.find_or_create_by!(blocked: other_user)
  end

  def unblock!(other_user)
    blocks_given.where(blocked: other_user).destroy_all
  end

  def verified?
    verified_at.present?
  end

  def verify_email!
    update!(verified_at: Time.current)
  end

  def send_verification_email
    UserMailer.email_verification(self).deliver_later
  end

  def send_password_reset_email
    UserMailer.password_reset(self).deliver_later
  end

  # Email change flow
  def update_email(new_email)
    return true if new_email.blank? || new_email.downcase == email_address

    if update(unconfirmed_email: new_email)
      send_email_reconfirmation
      true
    else
      false
    end
  end

  def send_email_reconfirmation
    return if bot?
    UserMailer.email_reconfirmation(self).deliver_later
  end

  def confirm_email_change!
    return unless unconfirmed_email.present?

    update!(email_address: unconfirmed_email, unconfirmed_email: nil)
  end

  def cancel_email_change!
    return unless unconfirmed_email.present?

    update!(unconfirmed_email: nil)
  end

  def pending_email_change?
    unconfirmed_email.present?
  end

  private
    def send_email_change_notification
      return if bot?
      old_email = email_address_before_last_save
      UserMailer.email_changed(self, old_email).deliver_later if old_email.present?
    end


    def grant_membership_to_open_rooms
      Membership.insert_all(Rooms::Open.active.pluck(:id).collect { |room_id| { room_id: room_id, user_id: id } })
      Rooms::Thread.joins(:parent_room).where(parent_room: { type: "Rooms::Open" }).find_each do |thread|
        thread.memberships.grant_to(self)
      end
    end

    def close_remote_connections(reconnect: false)
      if Campfire.saas? && ApplicationRecord.current_tenant.present?
        ActionCable.server.remote_connections.where(
          current_tenant: ApplicationRecord.current_tenant,
          current_user: self
        ).disconnect reconnect: reconnect
      else
        ActionCable.server.remote_connections.where(current_user: self).disconnect reconnect: reconnect
      end
    end

    # Clean up ALL associated records (including inactive ones) to satisfy FK constraints.
    #
    # Why this exists instead of `dependent: :destroy`:
    # Most associations have `-> { active }` scopes for soft deletion, so Rails'
    # `dependent: :destroy` only finds active records. We need to delete inactive
    # records too, hence the explicit unscoped queries.
    def destroy_all_associated_records
      # Delete messages first (they have FKs to boosts, bookmarks, mentions)
      Message.unscoped.where(creator_id: id).find_each(&:destroy)

      # Then delete other records with FKs to users
      Membership.unscoped.where(user_id: id).delete_all
      Bookmark.unscoped.where(user_id: id).delete_all
      Boost.unscoped.where(booster_id: id).delete_all
      Mention.where(user_id: id).delete_all
      Search.where(user_id: id).delete_all
      Search.where(creator_id: id).delete_all
      Session.where(user_id: id).delete_all
      AuthToken.where(user_id: id).delete_all
      Ban.where(user_id: id).delete_all
      Block.where(blocker_id: id).delete_all
      Block.where(blocked_id: id).delete_all
      Push::Subscription.where(user_id: id).delete_all
      Webhook.where(user_id: id).delete_all
      Mailkick::Subscription.where(subscriber: self).delete_all
    end

    def set_default_name
      self.name = name.presence || DEFAULT_NAME
    end

    def transliterate_name
      self.ascii_name = ActiveSupport::Inflector.transliterate(name.to_s)
    end

    def normalize_social_urls
      self.twitter_url = clean_twitter_url(twitter_url)
      self.linkedin_url = clean_linkedin_url(linkedin_url)
    end

    def clean_twitter_url(url)
      return nil if url.blank?
      return url.strip if url.include?("/")

      handle = url.gsub(/^@/, "").strip
      "https://x.com/#{handle}"
    end

    def clean_linkedin_url(url)
      return nil if url.blank?
      return url.strip if url.strip.match?(/\/.+/)

      handle = url.strip
      "https://www.linkedin.com/in/#{handle}"
    end

    # Returns Time.current if the timestamp is missing or stale (> 1 hour old).
    # Stale timestamps indicate the user left the inbox page open without interacting.
    def freshness_checked_time(iso8601_time)
      return Time.current unless iso8601_time.present?

      time = Time.iso8601(iso8601_time)
      time > 1.hour.ago ? time : Time.current
    end
end
