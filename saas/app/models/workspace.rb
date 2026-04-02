# frozen_string_literal: true

class Workspace < UntenantedRecord
  # Workspace registry in untenanted database
  #
  # Each workspace has:
  # - external_id: 7+ digit integer used in URLs (/1000001/rooms/general)
  # - name: Display name
  # - suspended_at: Set when workspace is suspended
  #
  # The actual workspace data (users, rooms, messages) lives in a separate
  # per-workspace SQLite database identified by external_id.

  belongs_to :creator, class_name: "GlobalIdentity"
  has_many :workspace_memberships, primary_key: :external_id, foreign_key: :tenant, dependent: :destroy
  has_many :backups, class_name: "Workspace::Backup"

  validates :name, presence: true, length: { maximum: 100 }
  validates :external_id, presence: true, uniqueness: true

  before_validation :assign_external_id, on: :create
  after_create_commit :send_welcome_email
  after_destroy_commit :purge_storage_later

  scope :active, -> { where(suspended_at: nil) }
  scope :suspended, -> { where.not(suspended_at: nil) }

  # URL prefix for this workspace (e.g., "/1000001")
  def slug
    "/#{external_id}"
  end

  def suspended?
    suspended_at.present?
  end

  def active?
    !suspended?
  end

  def current?
    external_id == ApplicationRecord.current_tenant&.to_i
  end

  def suspend!
    update!(suspended_at: Time.current)
  end

  def unsuspend!
    update!(suspended_at: nil)
  end

  # Create workspace with its database
  def self.create_with_database!(name:, creator:)
    transaction do
      # Lock the creator row to serialize concurrent workspace creation
      creator.lock!
      raise GlobalIdentity::WorkspaceLimitReachedError if creator.workspace_limit_reached?

      workspace = create!(
        name: name,
        creator: creator
      )

      tenant_id = workspace.external_id.to_s

      # Create the tenant database (skip if already exists)
      unless ApplicationRecord.tenant_exist?(tenant_id)
        ApplicationRecord.create_tenant(tenant_id)
      end

      # Create membership for creator
      membership = creator.workspace_memberships.find_or_create_by!(tenant: tenant_id)

      # Create initial data in the new workspace
      # Note: Uses find_or_create patterns to handle partial data from failed attempts
      # and stale tenant DBs reused during tests (same external_id due to sequence rollback)
      ApplicationRecord.with_tenant(tenant_id) do
        # Create or update Account (singleton per workspace)
        account = Account.find_or_initialize_by(singleton_guard: 0)
        account.update!(name: name) if account.name != name

        # Create or reactivate administrator User (linked to workspace_membership)
        # Uses unscoped to find deactivated users from stale tenant DBs
        admin_user = User.unscoped.find_or_initialize_by(email_address: creator.email_address)
        if admin_user.new_record?
          admin_user.assign_attributes(
            workspace_membership_id: membership.id,
            name: creator.name || creator.email_address.split("@").first.titleize,
            role: :administrator,
            verified_at: Time.current
          )
          admin_user.save!
        else
          admin_user.reactivate if admin_user.deactivated?
          admin_user.update!(workspace_membership_id: membership.id, role: :administrator)
        end

        # Deactivate any other users left from stale tenant DBs
        User.where.not(id: admin_user.id).find_each(&:deactivate)

        membership.cache_user_id!(admin_user.id)

        # Create default rooms (creator is required)
        Rooms::Open.find_or_create_by!(name: "General") do |room|
          room.slug = "general"
          room.creator = admin_user
          room.auto_join = true
        end
      end

      workspace
    end
  end



  # Check if user is the last admin (prevents leaving)
  def last_administrator?(user)
    ApplicationRecord.with_tenant(external_id.to_s) do
      User.active.administrator.count == 1 && user.administrator?
    end
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    false
  end

  # Full cleanup: take a final backup, then destroy
  def destroy_with_database!
    admin_emails = fetch_admin_emails
    create_final_backup
    destroy!  # Cascades to WorkspaceMemberships via dependent: :destroy
    admin_emails.each { |email| WorkspaceMailer.deleted(name, email).deliver_later }
  end

  private

    # Take a final backup, purge old daily backups, and detach the final record
    def create_final_backup
      if Workspace::Backup.r2_configured?
        backups.find_each(&:purge!)
        Workspace::Backup.create_from_database!(self, key_prefix: "final")
      end
      backups.update_all(workspace_id: nil)
    end

    def purge_storage_later
      Workspace::PurgeStorageJob.perform_later(external_id.to_s)
    end

    def assign_external_id
      self.external_id ||= Workspace::ExternalIdSequence.next_id
    end

    def fetch_admin_emails
      ApplicationRecord.with_tenant(external_id.to_s) do
        User.active.administrator.pluck(:email_address)
      end
    rescue ActiveRecord::Tenanted::TenantDoesNotExistError
      []
    end

    def send_welcome_email
      WorkspaceMailer.welcome(self).deliver_later
    end
end
