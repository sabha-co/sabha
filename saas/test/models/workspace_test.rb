# frozen_string_literal: true

require_relative "../test_helper"

class WorkspaceTest < ActiveSupport::TestCase
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

  test "last_administrator? returns false when tenant does not exist" do
    workspace = workspaces(:acme)
    user = User.new(role: :administrator)
    # No tenant DB exists for fixtures, so should return false safely
    assert_not workspace.last_administrator?(user)
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
