# frozen_string_literal: true

require_relative "../test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "requires name" do
    workspace = Workspace.new(external_id: 9999999, creator: global_identities(:alice))
    assert_not workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
  end

  test "auto-assigns external_id on create" do
    workspace = Workspace.create!(name: "New Workspace", creator: global_identities(:alice))
    assert workspace.external_id.present?
    assert workspace.external_id >= 1000001
  end

  test "external_id must be unique" do
    existing = workspaces(:acme)
    duplicate = Workspace.new(name: "Duplicate", external_id: existing.external_id, creator: global_identities(:bob))
    assert_not duplicate.valid?
  end

  test "slug returns path prefix" do
    workspace = workspaces(:acme)
    assert_equal "/1000001", workspace.slug
  end

  test "active? and suspended?" do
    assert workspaces(:acme).active?
    assert_not workspaces(:acme).suspended?

    assert workspaces(:suspended).suspended?
    assert_not workspaces(:suspended).active?
  end

  test "suspend! sets suspended_at" do
    workspace = workspaces(:acme)
    workspace.suspend!
    assert workspace.suspended?
  end

  test "unsuspend! clears suspended_at" do
    workspace = workspaces(:suspended)
    workspace.unsuspend!
    assert workspace.active?
  end

  test "active scope excludes suspended workspaces" do
    assert_includes Workspace.active, workspaces(:acme)
    assert_not_includes Workspace.active, workspaces(:suspended)
  end

  test "belongs_to creator" do
    workspace = workspaces(:acme)
    assert_equal global_identities(:alice), workspace.creator
  end

  test "has_many workspace_memberships" do
    workspace = workspaces(:shared)
    assert workspace.workspace_memberships.count >= 2
  end

  test "last_administrator? returns true when user is only admin" do
    with_provisioned_workspace(name: "Last Admin Test", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)
      user = ApplicationRecord.with_tenant(workspace.external_id.to_s) { User.find(membership.user_id) }

      assert workspace.last_administrator?(user)
    end
  end

  test "last_administrator? returns false when multiple admins exist" do
    with_provisioned_workspace(name: "Multi Admin Test", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :administrator)

      alice_membership = WorkspaceMembership.find_by(
        tenant: workspace.external_id.to_s,
        global_identity: global_identities(:alice)
      )

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        alice_user = User.find(alice_membership.user_id)
        assert_equal 2, User.active.administrator.count, "Expected 2 active admins"
        assert_not workspace.last_administrator?(alice_user)
      end
    end
  end

  test "last_administrator? returns false when tenant does not exist" do
    # Use a workspace with a tenant ID that is guaranteed to never have a database
    workspace = Workspace.create!(name: "No DB", external_id: 9999998, creator: global_identities(:alice))
    user = User.new(role: :administrator)
    assert_not workspace.last_administrator?(user)
  ensure
    workspace&.destroy
  end

  test "sends welcome email to creator after create" do
    assert_enqueued_emails 1 do
      Workspace.create!(name: "Email Test", creator: global_identities(:alice))
    end
  end

  # --- Workspace provisioning (create_with_database!) ---

  test "create_with_database! provisions a complete workspace" do
    creator = global_identities(:alice)

    with_provisioned_workspace(name: "Provisioning Test", creator: creator) do |workspace|
      tenant = workspace.external_id.to_s

      # Creates tenant database
      assert ApplicationRecord.tenant_exist?(tenant)

      # Creates Account with workspace name
      ApplicationRecord.with_tenant(tenant) do
        assert_equal "Provisioning Test", Account.first.name
      end

      # Creates admin user linked to creator, caches user_id on membership
      membership = creator.workspace_memberships.find_by(tenant: tenant)
      assert_not_nil membership
      assert_not_nil membership.user_id

      ApplicationRecord.with_tenant(tenant) do
        admin = User.find_by(email_address: creator.email_address)
        assert admin.administrator?
        assert admin.verified_at.present?
        assert_equal membership.id, admin.workspace_membership_id
        assert_equal admin.id, membership.user_id
      end

      # Creates default General room
      ApplicationRecord.with_tenant(tenant) do
        general = Rooms::Open.find_by(name: "General")
        assert_not_nil general
        assert_equal "general", general.slug
        assert general.auto_join?
      end
    end
  end

  test "destroy_with_database! removes workspace and destroys memberships" do
    workspace = Workspace.create_with_database!(
      name: "Test Workspace",
      creator: global_identities(:alice)
    )
    external_id = workspace.external_id

    # Verify workspace and membership exist
    assert Workspace.exists?(external_id: external_id)
    assert WorkspaceMembership.exists?(tenant: external_id.to_s)

    # Destroy
    workspace.destroy_with_database!

    # Verify cleanup
    assert_not Workspace.exists?(external_id: external_id)
    assert_not WorkspaceMembership.exists?(tenant: external_id.to_s)
  end

  # --- snapshot_database_to ---

  test "snapshot_database_to includes recent writes after a WAL checkpoint" do
    with_provisioned_workspace(name: "Snapshot Test", creator: global_identities(:alice)) do |workspace|
      tenant = workspace.external_id.to_s

      ApplicationRecord.with_tenant(tenant) do
        room = Rooms::Open.find_by!(name: "General")
        admin = User.find_by!(email_address: global_identities(:alice).email_address)
        room.messages.create!(creator: admin, body: ActionText::Content.new("hello world"))
      end

      live_message_count = ApplicationRecord.with_tenant(tenant) { Message.unscoped.count }

      Tempfile.create([ "snapshot", ".sqlite3" ]) do |tempfile|
        workspace.snapshot_database_to(tempfile.path)

        snapshot = SQLite3::Database.new(tempfile.path)
        begin
          assert_equal live_message_count, snapshot.execute("SELECT COUNT(*) FROM messages").first.first
          assert_equal 1, snapshot.execute("SELECT COUNT(*) FROM accounts").first.first
          assert_equal 1, snapshot.execute("SELECT COUNT(*) FROM rooms WHERE name = 'General'").first.first
        ensure
          snapshot.close
        end
      end
    end
  end

  test "snapshot_database_to preserves users.workspace_membership_id (sanitization is the caller's job)" do
    with_provisioned_workspace(name: "FK Preserve Test", creator: global_identities(:alice)) do |workspace|
      tenant = workspace.external_id.to_s

      live_ids = ApplicationRecord.with_tenant(tenant) do
        User.unscoped.order(:id).pluck(:workspace_membership_id)
      end
      assert live_ids.any?(&:present?), "test fixture must have at least one non-null workspace_membership_id"

      Tempfile.create([ "snapshot", ".sqlite3" ]) do |tempfile|
        workspace.snapshot_database_to(tempfile.path)

        snapshot = SQLite3::Database.new(tempfile.path)
        begin
          snapshot_ids = snapshot.execute("SELECT workspace_membership_id FROM users ORDER BY id").map(&:first)
          assert_equal live_ids, snapshot_ids
        ensure
          snapshot.close
        end
      end
    end
  end

  test "snapshot_database_to mirrors the live tenant schema and row counts" do
    with_provisioned_workspace(name: "Mirror Snapshot", creator: global_identities(:alice)) do |workspace|
      tenant = workspace.external_id.to_s

      live_counts, live_migrations = ApplicationRecord.with_tenant(tenant) do
        [
          {
            users: User.unscoped.count,
            rooms: Room.unscoped.count,
            messages: Message.unscoped.count
          },
          ApplicationRecord.connection.select_values("SELECT version FROM schema_migrations ORDER BY version")
        ]
      end

      Tempfile.create([ "snapshot", ".sqlite3" ]) do |tempfile|
        workspace.snapshot_database_to(tempfile.path)

        snapshot = SQLite3::Database.new(tempfile.path)
        begin
          assert_equal live_counts[:users], snapshot.execute("SELECT COUNT(*) FROM users").first.first
          assert_equal live_counts[:rooms], snapshot.execute("SELECT COUNT(*) FROM rooms").first.first
          assert_equal live_counts[:messages], snapshot.execute("SELECT COUNT(*) FROM messages").first.first

          snapshot_migrations = snapshot.execute("SELECT version FROM schema_migrations ORDER BY version").map(&:first)
          assert_equal live_migrations, snapshot_migrations
        ensure
          snapshot.close
        end
      end
    end
  end

  # --- export_for_self_host ---

  test "export_for_self_host clears users.workspace_membership_id on the snapshot" do
    with_provisioned_workspace(name: "Self-host Export Test", creator: global_identities(:alice)) do |workspace|
      tenant = workspace.external_id.to_s

      live_count = ApplicationRecord.with_tenant(tenant) do
        User.unscoped.where.not(workspace_membership_id: nil).count
      end
      assert_operator live_count, :>, 0, "fixture should have at least one user with workspace_membership_id set"

      Tempfile.create([ "export", ".sqlite3" ]) do |tempfile|
        workspace.export_for_self_host(tempfile.path)

        snapshot = SQLite3::Database.new(tempfile.path)
        begin
          non_null = snapshot.execute("SELECT COUNT(*) FROM users WHERE workspace_membership_id IS NOT NULL").first.first
          assert_equal 0, non_null
        ensure
          snapshot.close
        end
      end
    end
  end

  # --- export request rate limit ---

  test "recently_exported? is false before any request" do
    assert_not workspaces(:acme).recently_exported?
  end

  test "request_export! enqueues and stamps last_export_requested_at" do
    workspace = workspaces(:acme)
    freeze_time = Time.current

    assert_enqueued_with(job: Workspace::ExportJob, args: [ workspace, "admin@example.com" ]) do
      travel_to(freeze_time) do
        workspace.request_export!("admin@example.com")
      end
    end

    assert workspace.recently_exported?
    assert_in_delta freeze_time.to_f, workspace.last_export_requested_at.to_f, 1.0
  end

  test "request_export! raises ExportThrottled and does not enqueue when cooldown is active" do
    workspace = workspaces(:acme)
    workspace.request_export!("first@example.com")

    assert_no_enqueued_jobs only: Workspace::ExportJob do
      assert_raises(Workspace::ExportThrottled) do
        workspace.request_export!("second@example.com")
      end
    end
  end

  test "request_export! does not stamp last_export_requested_at if perform_later raises" do
    workspace = workspaces(:acme)
    Workspace::ExportJob.stubs(:perform_later).raises(StandardError, "queue down")

    assert_raises(StandardError) do
      workspace.request_export!("admin@example.com")
    end

    assert_nil workspace.reload.last_export_requested_at,
      "no marker should be written so the next attempt isn't blocked by a phantom request"
  end

  test "recently_exported? returns false after EXPORT_COOLDOWN elapses" do
    workspace = workspaces(:acme)
    workspace.request_export!("admin@example.com")

    travel_to(Time.current + Workspace::EXPORT_COOLDOWN + 1.minute) do
      assert_not workspace.recently_exported?
    end
  end

  test "export_for_self_host does not mutate the live tenant database" do
    with_provisioned_workspace(name: "Self-host Non-mutate Test", creator: global_identities(:alice)) do |workspace|
      tenant = workspace.external_id.to_s

      before_ids = ApplicationRecord.with_tenant(tenant) { User.unscoped.order(:id).pluck(:workspace_membership_id) }
      assert before_ids.any?(&:present?)

      Tempfile.create([ "export", ".sqlite3" ]) do |tempfile|
        workspace.export_for_self_host(tempfile.path)
      end

      after_ids = ApplicationRecord.with_tenant(tenant) { User.unscoped.order(:id).pluck(:workspace_membership_id) }
      assert_equal before_ids, after_ids
    end
  end
end
