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
      alice_user = ApplicationRecord.with_tenant(workspace.external_id.to_s) { User.find(alice_membership.user_id) }

      assert_not workspace.last_administrator?(alice_user)
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

  test "create_with_database! creates tenant database" do
    with_provisioned_workspace(name: "Provisioning Test", creator: global_identities(:alice)) do |workspace|
      assert ApplicationRecord.tenant_exist?(workspace.external_id.to_s)
    end
  end

  test "create_with_database! creates Account with workspace name" do
    with_provisioned_workspace(name: "Account Test", creator: global_identities(:alice)) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        account = Account.first
        assert_not_nil account
        assert_equal "Account Test", account.name
      end
    end
  end

  test "create_with_database! creates admin user linked to creator" do
    creator = global_identities(:alice)
    with_provisioned_workspace(name: "Admin User Test", creator: creator) do |workspace|
      membership = creator.workspace_memberships.find_by(tenant: workspace.external_id.to_s)
      assert_not_nil membership

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        admin = User.find_by(email_address: creator.email_address)
        assert_not_nil admin
        assert admin.administrator?
        assert admin.verified_at.present?
        assert_equal membership.id, admin.workspace_membership_id
      end
    end
  end

  test "create_with_database! caches user_id on membership" do
    creator = global_identities(:alice)
    with_provisioned_workspace(name: "Cache User ID Test", creator: creator) do |workspace|
      membership = creator.workspace_memberships.find_by(tenant: workspace.external_id.to_s)
      assert_not_nil membership.user_id

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        user = User.find_by(email_address: creator.email_address)
        assert_equal user.id, membership.user_id
      end
    end
  end

  test "create_with_database! creates default General room" do
    with_provisioned_workspace(name: "Default Room Test", creator: global_identities(:alice)) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
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
end
