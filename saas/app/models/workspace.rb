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
  has_one :snapshot, class_name: "Workspace::Snapshot", dependent: :destroy

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

  # Collect activity metrics from tenant DB and upsert into workspace_snapshots
  def refresh_snapshot!
    metrics = ApplicationRecord.with_tenant(external_id.to_s) do
      {
        messages_24h: Message.active.user_authored.since(24.hours.ago).count,
        messages_7d: Message.active.user_authored.since(7.days.ago).count,
        active_users: User.active.count,
        storage_bytes: (Account.sole.bytes_used rescue 0)
      }
    end

    db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{external_id}/db/main.sqlite3")
    metrics[:database_size] = File.exist?(db_path) ? File.size(db_path) : 0

    Workspace::Snapshot.upsert(
      { workspace_id: id, **metrics, created_at: Time.current, updated_at: Time.current },
      unique_by: :workspace_id
    )

    reload_snapshot
  end

  # Most recent activity across all workspace members (via GlobalSession)
  def last_active_at
    GlobalSession
      .joins("INNER JOIN workspace_memberships ON workspace_memberships.global_identity_id = global_sessions.global_identity_id")
      .where(workspace_memberships: { tenant: external_id.to_s })
      .maximum(:last_active_at)
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

  # Path to this workspace's SQLite database file
  def database_path
    Rails.root.join("storage/workspaces/#{Rails.env}/#{external_id}/db/main.sqlite3")
  end

  # Write a clean SQLite copy of the tenant database to dest_path. Runs a WAL
  # checkpoint first so the snapshot includes all committed writes.
  #
  # Pure copy — never mutates the snapshot. Workspace::Backup uses this directly
  # because backups are restored back into the same SaaS instance and the
  # cross-database FKs (e.g. users.workspace_membership_id) must remain intact.
  def snapshot_database_to(dest_path)
    ApplicationRecord.with_tenant(external_id.to_s) do
      ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
    end

    source_db = SQLite3::Database.new(database_path.to_s)
    dest_db = SQLite3::Database.new(dest_path.to_s)
    sqlite_backup = SQLite3::Backup.new(dest_db, "main", source_db, "main")
    sqlite_backup.step(-1)
    sqlite_backup.finish
  ensure
    source_db&.close
    dest_db&.close
  end

  # Cooldown window between admin-triggered self-host exports per workspace.
  # Stops accidental double-clicks from spawning duplicate jobs and accumulating
  # short-lived dumps in R2.
  EXPORT_COOLDOWN = 1.hour

  # Cached marker of the most recent export request, or nil. Returns
  # { email:, at: } when a request is still inside the cooldown window.
  # Read-only — view layer uses this to decide whether to render the button.
  def recent_export_request
    Rails.cache.read(export_request_cache_key)
  end

  # Atomic "claim a cooldown slot and enqueue an export" — the read-then-write
  # alternative would let two concurrent admins both observe nil and both
  # enqueue. Returns nil when this caller successfully claimed and enqueued, or
  # the existing { email:, at: } hash if the cooldown was already active.
  #
  # Claim is rolled back if perform_later raises so a queue outage doesn't
  # leave a phantom request blocking the next hour.
  def request_export(email)
    return recent_export_request unless claim_export_request(email)

    begin
      Workspace::ExportJob.perform_later(self, email)
      nil
    rescue StandardError
      Rails.cache.delete(export_request_cache_key)
      raise
    end
  end

  # Snapshot + scrub cross-database references so the file is portable to a
  # self-hosted Sabha install. users.workspace_membership_id points at the
  # SaaS-only untenanted workspace_memberships table; clearing it leaves no
  # dangling references once the SQLite is detached from SaaS.
  def export_for_self_host(dest_path)
    snapshot_database_to(dest_path)

    db = SQLite3::Database.new(dest_path.to_s)
    db.execute("UPDATE users SET workspace_membership_id = NULL")
  ensure
    db&.close
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

  # Workspace deletion sequence:
  #
  # 1. Capture admin emails from tenanted DB (before it's destroyed)
  # 2. Purge old daily R2 backups, create a final backup, detach backup records
  # 3. Destroy workspace record (cascades to WorkspaceMemberships)
  # 4. Email all admins that the workspace has been deleted
  # 5. (async) Purge ActiveStorage blobs and delete the tenant SQLite database
  #    via Workspace::PurgeStorageJob (after_destroy_commit)
  def destroy_with_database!
    admin_emails = fetch_admin_emails
    create_final_backup
    destroy!
    admin_emails.each { |email| WorkspaceMailer.deleted(name, email).deliver_later }
  end

  private

    # Take a final backup, purge old daily backups, and detach the final record
    def create_final_backup
      if Workspace::R2.configured?
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

    # Atomic compare-and-set against the cache. Returns true if this caller
    # claimed the cooldown slot, false if a value was already present.
    def claim_export_request(email)
      Rails.cache.write(
        export_request_cache_key,
        { email: email, at: Time.current },
        expires_in: EXPORT_COOLDOWN,
        unless_exist: true
      )
    end

    def export_request_cache_key
      "workspace/#{external_id}/export_request"
    end

    def send_welcome_email
      WorkspaceMailer.welcome(self).deliver_later
    end
end
