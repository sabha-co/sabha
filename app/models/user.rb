class User < ApplicationRecord
  DEFAULT_NAME = "New Member"
  MINIMUM_PASSWORD_LENGTH = 8

  include Avatar, Bannable, Blockable, Bot, DicebearAvatar, EmailChangeable, Mentionable, Notifiable, PasswordAuthable, Role, Streakable, Transferable, Verifiable

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
    record = SingleSignOnRecord.find_or_provision!(payload)
    record.require_activation!(payload)
    record.user
  end

  # User status enum (replaces active boolean + suspended_at)
  enum :status, %i[active deactivated banned], default: :active

  has_many :memberships, -> { active }, class_name: "Membership"
  has_many :rooms, -> { active }, through: :memberships, source: :room

  has_many :bookmarks, class_name: "Bookmark"
  has_many :bookmarked_messages, -> { order("bookmarks.created_at DESC") }, through: :bookmarks, source: :message
  has_many :reachable_messages, through: :rooms, source: :messages
  has_many :messages, -> { active }, foreign_key: :creator_id, class_name: "Message"

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
      .where(
        "EXISTS (SELECT 1 FROM notifications WHERE notifications.message_id = messages.id
          AND notifications.user_id = ? AND notifications.activity_type = 'mention')
         OR messages.mentions_everyone = ?
         OR EXISTS (SELECT 1 FROM rooms WHERE rooms.id = messages.room_id AND rooms.type = 'Rooms::Direct')",
        id, true
      )
  end

  has_many :push_subscriptions, class_name: "Push::Subscription", dependent: :delete_all

  has_many :boosts, foreign_key: :booster_id, class_name: "Boost"
  has_many :searches, dependent: :delete_all

  has_many :sessions, dependent: :destroy
  has_many :auth_tokens, dependent: :destroy
  has_many :bans, dependent: :destroy
  has_one :single_sign_on_record, dependent: :destroy

  belongs_to :badge, optional: true

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email_address, presence: true, if: :person?
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email_address.present? }
  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  scope :without_default_names, -> { where.not(name: DEFAULT_NAME) }

  after_update :sync_name_to_global_identity, if: -> { Sabha.saas? && saved_change_to_name? }
  after_update_commit :sync_workspace_membership_active, if: -> { Sabha.saas? && saved_change_to_status? }

  before_validation :set_default_name
  before_validation :normalize_social_urls
  before_save :transliterate_name, if: :name_changed?
  after_create_commit :grant_membership_to_open_rooms

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
end
