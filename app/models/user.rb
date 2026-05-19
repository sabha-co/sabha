class User < ApplicationRecord
  DEFAULT_NAME = "New Member"
  MINIMUM_PASSWORD_LENGTH = 8

  class SingleSignOnError < StandardError
    attr_reader :user_message, :status

    def initialize(message = "Unable to sign in with SSO.", user_message: "Single sign-on failed.", status: :unauthorized)
      super(message)
      @user_message = user_message
      @status = status
    end
  end

  class SingleSignOnForbidden < SingleSignOnError; end

  class SingleSignOnFailed < SingleSignOnError
    def initialize(message = "The SSO provider rejected the sign-in.")
      super(message, user_message: "Single sign-on failed.")
    end
  end

  class SingleSignOnActivationRequired < SingleSignOnError
    def initialize(message = "SSO email verification is required.")
      super(message, user_message: "Please verify your email address before signing in.")
    end
  end

  include Avatar, Bannable, Bot, DicebearAvatar, Mentionable, Role, Transferable

  serialize :preferences, coder: JSON

  # SaaS mode: Link to GlobalIdentity via WorkspaceMembership
  # In single-tenant mode, workspace_membership_id is nil
  belongs_to :workspace_membership, optional: true, class_name: "WorkspaceMembership"

  # Access GlobalIdentity through WorkspaceMembership (SaaS mode)
  def global_identity
    return nil unless Sabha.saas?
    workspace_membership&.global_identity
  end

  def self.sign_in_with_sso!(payload)
    SingleSignOnRecord.find_or_provision!(payload).user
  end

  # User status enum (replaces active boolean + suspended_at)
  enum :status, %i[active deactivated banned], default: :active

  has_many :memberships, -> { active }, class_name: "Membership"
  has_many :rooms, -> { active }, through: :memberships, source: :room

  has_many :bookmarks, class_name: "Bookmark"
  has_many :bookmarked_messages, -> { order("bookmarks.created_at DESC") }, through: :bookmarks, source: :message
  has_many :reachable_messages, through: :rooms, source: :messages
  has_many :messages, -> { active }, foreign_key: :creator_id, class_name: "Message"

  has_many :notifications
  has_many :notification_bundles, class_name: "Notification::Bundle", dependent: :destroy
  has_many :join_codes, class_name: "Account::JoinCode", dependent: :destroy

  has_one :notification_settings, class_name: "User::NotificationSettings", dependent: :destroy
  after_create_commit :ensure_notification_settings

  # Returns the user's open accumulator for missed-notification email candidates,
  # opening one if none is active. Race-safe via the partial unique index — a
  # concurrent open by a parallel writer raises RecordNotUnique on the loser
  # and falls through to a second read.
  def active_notification_bundle
    notification_bundles.active.first || open_notification_bundle!
  end

  # Public so batch dispatch can open bundles for users not in a pre-fetched
  # active set without re-running `active.first` for each miss.
  def open_notification_bundle!
    frequency = notification_settings&.email_frequency || "hourly"
    starts_at = Time.current
    notification_bundles.create!(
      frequency: frequency,
      starts_at: starts_at,
      ends_at:   starts_at + Notification::Bundle::FREQUENCY_WINDOWS.fetch(frequency)
    )
  rescue ActiveRecord::RecordNotUnique
    notification_bundles.active.first!
  end

  def unsubscribe_from_email!(surface)
    (notification_settings || create_notification_settings!).unsubscribe_from!(surface)
  end

  # Builds this user's weekly digest content and mails it if non-empty.
  # `last_digest_sent_at` only advances on actual delivery so quiet weeks
  # don't dedup-lock subsequent runs.
  def deliver_weekly_digest_now
    content = Notification::Digest::Content.new(self)
    return if content.empty?

    WeeklyDigestMailer.digest(self, content).deliver_now
    notification_settings.update!(last_digest_sent_at: Time.current)
  end

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
      .where(
        "EXISTS (SELECT 1 FROM notifications WHERE notifications.message_id = messages.id
          AND notifications.user_id = ? AND notifications.activity_type = 'mention')
         OR messages.mentions_everyone = ?
         OR EXISTS (SELECT 1 FROM rooms WHERE rooms.id = messages.room_id AND rooms.type = 'Rooms::Direct')",
        id, true
      )
  end

  # Marks rooms with unread activity (mentions, boosts, thread replies) as read.
  # DMs are handled separately by mark_direct_messages_as_read.
  # Only marks as read if there were no non-notified messages in the window
  # (avoids accidentally marking unread messages as read when user only viewed activity)
  def mark_activity_as_read(loaded_at)
    mark_notified_rooms_as_read(freshness_checked_time(loaded_at))
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
  # if the room had no non-notified messages in the window (avoids accidentally marking
  # unread messages as read when user only viewed activity)
  def mark_inbox_as_read(messages_loaded_at:, notifications_loaded_at:, activity_loaded_at:)
    messages_until = freshness_checked_time(messages_loaded_at)
    notifications_until = freshness_checked_time(notifications_loaded_at)
    activity_until = freshness_checked_time(activity_loaded_at)

    # Mark all visible rooms as read up to when messages were loaded
    memberships.unread.each { |m| m.read_until(messages_until) }

    # Mark notification rooms as read up to when notifications were loaded
    memberships.notifications_on.unread.each { |m| m.read_until(notifications_until) }

    # Mark activity rooms as read: DMs always, others only if all unread messages have notifications
    mark_notified_rooms_as_read(activity_until, include_dms: true)
  end

  has_many :push_subscriptions, class_name: "Push::Subscription", dependent: :delete_all

  has_many :boosts, foreign_key: :booster_id, class_name: "Boost"
  has_many :searches, dependent: :delete_all

  has_many :sessions, dependent: :destroy
  has_many :auth_tokens, dependent: :destroy
  has_many :bans, dependent: :destroy
  has_one :single_sign_on_record, dependent: :destroy

  belongs_to :badge, optional: true

  has_many :blocks_given, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocked_users, through: :blocks_given, source: :blocked

  has_many :blocks_received, class_name: "Block", foreign_key: :blocked_id, dependent: :destroy
  has_many :blocked_by_users, through: :blocks_received, source: :blocker

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email_address, presence: true, if: :person?
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email_address.present? }
  validates :unconfirmed_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }
  normalizes :unconfirmed_email, with: ->(email) { email&.strip&.downcase }

  scope :without_default_names, -> { where.not(name: DEFAULT_NAME) }
  scope :verified, -> { where.not(verified_at: nil) }
  scope :unverified, -> { where(verified_at: nil) }

  scope :weekly_digest_eligible, -> {
    verified
      .where(status: statuses[:active])
      .where.not(role: roles[:bot])
      .joins(:notification_settings)
      .includes(:notification_settings)
      .where(user_notification_settings: { weekly_digest_subscribed: true })
      .merge(User::NotificationSettings.due_for_weekly_digest)
  }

  has_secure_password validations: false
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, if: -> { password.present? }

  generates_token_for :email_verification, expires_in: 24.hours
  generates_token_for :email_change, expires_in: 24.hours
  generates_token_for :password_reset, expires_in: 1.hour do
    password_salt&.last(10)
  end

  after_update :send_email_change_notification, if: :saved_change_to_email_address?
  after_update :sync_name_to_global_identity, if: -> { Sabha.saas? && saved_change_to_name? }
  after_update_commit :sync_workspace_membership_active, if: -> { Sabha.saas? && saved_change_to_status? }

  before_validation :set_default_name
  before_validation :normalize_social_urls
  before_save :transliterate_name, if: :name_changed?
  after_create_commit :grant_membership_to_open_rooms
  after_create_commit :post_welcome_message

  scope :ordered, -> { order(arel_table[:role].desc, arel_table[:name].lower) }
  scope :recent_posters_first, ->(room_id = nil) do
    messages_table = Message.active.arel_table
    users_table = active.arel_table

    left_join_condition = messages_table[:creator_id].eq(users_table[:id])
      .and(messages_table[:event].eq(nil))
      .and(messages_table[:welcome].eq(false))  # Mirrors Message.user_authored scope
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

  # Exact first-name matches ranked above partial matches. Both legs capped at limit.
  def self.matching(query, limit: 20)
    return [] if query.blank?
    (by_first_name(query).limit(limit) + filtered_by(query).limit(limit)).uniq.first(limit)
  end

  scope :sharing_rooms_with, ->(user) {
    joins(:memberships).where(memberships: { room_id: user.rooms.select(:id) }).distinct
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
      reactivate_direct_rooms
      update! status: :active
      reset_remote_connections
    end
  end

  def deactivate
    transaction do
      revoke_access
      deactivate_direct_rooms
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

  # Email-only presence check — true when no membership in this workspace has
  # been connected within the away tier (1 hour). Push uses the tighter
  # 60-second `connected?` instead.
  def workspace_locally_away?
    Membership.workspace_locally_away?(id)
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
           .user_authored
           .joins(:room)
           .where(creator_id: id)
           .where("rooms.type != ?", "Rooms::Direct")
           .count
  end

  def current_streak
    if streak_updated_on.nil?
      super # Pre-existing rows: preserve until next recalculation
    elsif streak_updated_on < Date.yesterday
      0
    else
      super
    end
  end

  def recalculate_streak!(excluding_message: nil)
    # Skip if user already posted today (excluding the message that triggered this callback)
    return if posted_on?(Date.current, excluding: excluding_message)

    new_streak = posted_on?(Date.yesterday) ? current_streak + 1 : 1
    update_columns(current_streak: new_streak, streak_updated_on: Date.current)
  end

  def posted_on?(date, excluding: nil)
    scope = messages.joins(:room)
                    .joins("LEFT JOIN messages AS parent_messages ON rooms.parent_message_id = parent_messages.id")
                    .joins("LEFT JOIN rooms AS parent_rooms ON parent_messages.room_id = parent_rooms.id")
                    .where.not(rooms: { type: "Rooms::Direct" })
                    .where("parent_rooms.type IS NULL OR parent_rooms.type != ?", "Rooms::Direct")
                    .where("DATE(messages.created_at) = ?", date)
                    .user_authored
    scope = scope.where.not(id: excluding.id) if excluding
    scope.exists?
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
    block = blocks_given.find_or_create_by!(blocked: other_user)
    dm_room_with(other_user)&.post_system_message(event: "user_blocked", body: "blocked #{other_user.name}", actor: self) if block.previously_new_record?
  end

  def unblock!(other_user)
    count = blocks_given.where(blocked: other_user).delete_all
    dm_room_with(other_user)&.post_system_message(event: "user_unblocked", body: "unblocked #{other_user.name}", actor: self) if count > 0
  end

  def verified?
    verified_at.present?
  end

  def verify_email!
    update!(verified_at: Time.current)
    post_welcome_message
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
    # Mirror User#active? onto the untenanted WorkspaceMembership row so the
    # workspace selector can filter without cross-tenant queries. Runs post-
    # commit, so a Postgres failure here cannot roll back the SQLite write.
    # The auth-time guard reads the tenanted User row, so a stale mirror can
    # only hide a workspace the user should still see — repaired by the
    # workspace_membership:backfill_user_active rake task.
    def sync_workspace_membership_active
      workspace_membership&.update_column(:user_active, active?)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("Failed to mirror user_active for workspace_membership=#{workspace_membership_id}: #{e.message}")
    end

    def deactivate_direct_rooms
      Membership.where(user_id: id).direct_rooms.each do |membership|
        membership.room.deactivate
      end
    end

    def reactivate_direct_rooms
      Membership.unscoped.where(user_id: id, active: false).direct_rooms.each do |membership|
        membership.room.reactivate
      end
    end

    def send_email_change_notification
      return if bot?
      old_email = email_address_before_last_save
      UserMailer.email_changed(self, old_email).deliver_later if old_email.present?
    end

    def sync_name_to_global_identity
      global_identity&.update!(name: name)
    rescue => error
      Rails.logger.error "[GlobalIdentity sync] Failed to sync name for User##{id}: #{error.message}"
    end

    def grant_membership_to_open_rooms
      forced_room_ids = Rooms::Open.active.where(auto_join: true).pluck(:id)
      return if forced_room_ids.empty?

      Membership.insert_all(forced_room_ids.collect { |room_id| { room_id: room_id, user_id: id } })
      Rooms::Thread.joins(:parent_room).where(parent_room: { type: "Rooms::Open", auto_join: true }).find_each do |thread|
        thread.memberships.grant_to(self)
      end
    end

    def post_welcome_message
      return unless bot? || verified?
      return unless room = Room.original

      room.post_welcome_message(user: self)
    end

    def dm_room_with(other_user)
      Rooms::Direct.find_by(members_hash: Rooms::Direct.members_hash_for(User.where(id: [ id, other_user.id ])))
    end

    def close_remote_connections(reconnect: false)
      if Sabha.saas? && ApplicationRecord.current_tenant.present?
        ActionCable.server.remote_connections.where(
          current_tenant: ApplicationRecord.current_tenant,
          current_user: self
        ).disconnect reconnect: reconnect
      else
        ActionCable.server.remote_connections.where(current_user: self).disconnect reconnect: reconnect
      end
    end

    # Clean up all associated records to satisfy FK constraints.
    #
    # Why this exists instead of `dependent: :destroy`:
    # Some associations have `-> { active }` scopes for soft deletion, so Rails'
    # `dependent: :destroy` only finds active records. We need to delete all
    # records regardless, hence the explicit queries.
    def destroy_all_associated_records
      # Clear cached user_id and flip user_active on WorkspaceMembership (SaaS mode).
      # user_active mirrors User#active? but the after_*_commit callback only fires on
      # status changes — a hard destroy must explicitly drop the mirror or the
      # workspace selector keeps surfacing an orphaned membership row.
      if Sabha.saas? && workspace_membership_id.present?
        WorkspaceMembership.where(id: workspace_membership_id, user_id: id)
                           .update_all(user_id: nil, user_active: false)
      end

      # Delete messages first (they have FKs to boosts, bookmarks, notifications)
      Message.unscoped.where(creator_id: id).find_each(&:destroy)

      # Then delete other records with FKs to users
      Notification.where(user_id: id).delete_all
      Notification.where(actor_id: id).delete_all
      Membership.unscoped.where(user_id: id).delete_all
      Bookmark.where(user_id: id).delete_all
      Boost.where(booster_id: id).delete_all
      Search.where(user_id: id).delete_all
      Search.where(creator_id: id).delete_all
      Session.where(user_id: id).delete_all
      AuthToken.where(user_id: id).delete_all
      Ban.where(user_id: id).delete_all
      Block.where(blocker_id: id).delete_all
      Block.where(blocked_id: id).delete_all
      Push::Subscription.where(user_id: id).delete_all
      Webhook.where(user_id: id).delete_all

      # Bundle items where this user was the actor (in any user's bundle).
      Notification::BundleItem.where(actor_id: id).delete_all

      # Bundles this user owns — items must go first to satisfy the FK.
      owned_bundle_ids = Notification::Bundle.where(user_id: id).pluck(:id)
      Notification::BundleItem.where(bundle_id: owned_bundle_ids).delete_all
      Notification::Bundle.where(user_id: id).delete_all

      User::NotificationSettings.where(user_id: id).delete_all
    end

    def ensure_notification_settings
      create_notification_settings! unless notification_settings
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

    # Marks rooms as read where all unread messages have corresponding notifications.
    # For non-DM rooms, only marks as read if there are no non-notified messages in the window.
    def mark_notified_rooms_as_read(until_time, include_dms: false)
      notified_room_ids = notifications
        .where("notifications.created_at <= ?", until_time)
        .joins(:message).distinct.pluck(Arel.sql("messages.room_id"))

      memberships.unread.includes(:room).where(room_id: notified_room_ids).each do |m|
        if m.room.is_a?(Rooms::Direct)
          m.read_until(until_time) if include_dms
          next
        end

        notified_message_ids = Notification.where(user: self)
          .where(message_id: m.room.messages.without_events.between(m.unread_at, until_time).select(:id))
          .pluck(:message_id)

        non_notified = m.room.messages.without_events
          .where.not(id: notified_message_ids)
          .between(m.unread_at, until_time)

        if non_notified.none?
          m.read_until(until_time)
        else
          m.clear_unread_notifications_until(until_time)
        end
      end
    end

    # Returns Time.current if the timestamp is missing or stale (> 1 hour old).
    # Stale timestamps indicate the user left the inbox page open without interacting.
    def freshness_checked_time(iso8601_time)
      return Time.current unless iso8601_time.present?

      time = Time.iso8601(iso8601_time)
      time > 1.hour.ago ? time : Time.current
    end
end
