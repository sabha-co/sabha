# frozen_string_literal: true

class GlobalIdentity < UntenantedRecord
  # Cross-workspace user authentication
  #
  # GlobalIdentity handles "who is this person?" across all workspaces.
  # Each workspace has a User record for workspace-specific data (name, role).
  #
  # MVP: Email + OTP only (no password)
  # v2: Add password_digest for optional password auth

  MAX_WORKSPACES = 10

  class WorkspaceLimitReachedError < StandardError; end

  has_many :global_sessions, dependent: :destroy
  has_many :auth_codes, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy

  validates :email_address, presence: true,
                           uniqueness: { case_sensitive: false },
                           format: { with: URI::MailTo::EMAIL_REGEXP }

  normalizes :name, with: ->(name) { name&.strip.presence }
  normalizes :email_address, with: ->(email) { email.strip.downcase }
  normalizes :unconfirmed_email, with: ->(email) { email&.strip&.downcase }

  validates :unconfirmed_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :verified, -> { where.not(verified_at: nil) }
  scope :superadmin, -> { where(superadmin: true) }

  SUPERADMIN_DOMAINS = %w[sabha.co superforum.io].freeze

  def superadmin?
    superadmin && SUPERADMIN_DOMAINS.include?(email_domain)
  end

  def email_domain
    email_address.split("@").last
  end

  def verified?
    verified_at.present?
  end

  def verify!
    update!(verified_at: Time.current) unless verified?
  end

  def workspace_limit_reached?
    Workspace.where(creator: self).count >= MAX_WORKSPACES
  end

  def workspaces
    workspace_memberships.includes(:workspace).filter_map(&:workspace)
  end

  def active_workspaces_recent_first
    workspace_memberships
      .includes(:workspace)
      .order(updated_at: :desc)
      .filter_map(&:workspace)
      .select(&:active?)
  end

  # Get workspace memberships in user-defined order (for workspace selector)
  def workspace_memberships_ordered
    workspace_memberships.ordered.includes(:workspace)
  end

  # Get workspace memberships with valid workspaces (filters orphaned memberships)
  def workspace_memberships_with_workspaces
    workspace_memberships.ordered.includes(:workspace).select { |m| m.workspace.present? }
  end

  # Email change flow (mirrors User#update_email pattern)
  def pending_email_change?
    unconfirmed_email.present?
  end

  # Confirms pending email change, syncs to workspaces
  # Returns [old_email, new_email] on success, nil if no pending change
  def confirm_email_change!
    return nil unless unconfirmed_email.present?

    old_email = email_address
    new_email = unconfirmed_email

    transaction do
      update!(email_address: new_email, unconfirmed_email: nil)
      sync_email_to_workspaces(new_email)
    end

    notify_email_changed(old_email, new_email)

    [ old_email, new_email ]
  end

  # Sync email to all workspace User records
  # Best-effort: logs failures but doesn't halt on errors
  def sync_email_to_workspaces(new_email = email_address)
    workspace_memberships.find_each do |membership|
      next if membership.user_id.blank?

      ApplicationRecord.with_tenant(membership.tenant) do
        user = User.find_by(id: membership.user_id)
        user&.update_column(:email_address, new_email)
      end
    rescue ActiveRecord::Tenanted::TenantDoesNotExistError
      # Workspace database doesn't exist, skip silently
    rescue => e
      Rails.logger.error("[GlobalIdentity#sync_email] Failed to sync email for membership #{membership.id} in tenant #{membership.tenant}: #{e.message}")
    end
  end

  def cancel_email_change!
    return unless unconfirmed_email.present?

    update!(unconfirmed_email: nil)
  end

  # Initiate an email change flow
  # Returns true if change initiated, false if no change needed
  # Raises ActiveRecord::RecordInvalid on validation errors
  # Handles auth code creation and email sending
  def initiate_email_change!(new_email)
    normalized = self.class.normalize_value_for(:email_address, new_email.to_s)

    if normalized.blank?
      errors.add(:email_address, :blank)
      raise ActiveRecord::RecordInvalid, self
    end

    if normalized == email_address
      cancel_email_change! if pending_email_change?
      return false
    end

    unless self.class.email_available?(normalized, excluding_id: id)
      errors.add(:email_address, :taken)
      raise ActiveRecord::RecordInvalid, self
    end

    self.unconfirmed_email = normalized
    save!

    auth_code = auth_codes.create!(purpose: :email_change)
    AuthCodeMailer.code(auth_code).deliver_later
    true
  end

  def notify_email_changed(old_email, new_email)
    WorkspaceMailer.email_changed(self, old_email, new_email).deliver_later
  end

  # Check if email is available (not taken as primary email by another user)
  def self.email_available?(email, excluding_id: nil)
    normalized = normalize_value_for(:email_address, email.to_s)
    scope = excluding_id ? where.not(id: excluding_id) : all
    !scope.exists?(email_address: normalized)
  end
end
