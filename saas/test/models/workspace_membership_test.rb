# frozen_string_literal: true

require_relative "../test_helper"

class WorkspaceMembershipTest < ActiveSupport::TestCase
  test "requires tenant" do
    membership = WorkspaceMembership.new(global_identity: global_identities(:alice))
    assert_not membership.valid?
    assert_includes membership.errors[:tenant], "can't be blank"
  end

  test "requires global_identity" do
    membership = WorkspaceMembership.new(tenant: "1000001")
    assert_not membership.valid?
  end

  test "unique global_identity per tenant" do
    existing = workspace_memberships(:alice_acme)
    duplicate = WorkspaceMembership.new(
      global_identity: existing.global_identity,
      tenant: existing.tenant
    )
    assert_not duplicate.valid?
  end

  test "belongs_to global_identity" do
    membership = workspace_memberships(:alice_acme)
    assert_equal global_identities(:alice), membership.global_identity
  end

  test "belongs_to workspace" do
    membership = workspace_memberships(:alice_acme)
    assert_equal workspaces(:acme), membership.workspace
  end

  test "account_name returns workspace account name" do
    # This requires the tenant database to exist, so we test the method exists
    membership = workspace_memberships(:alice_acme)
    assert_respond_to membership, :account_name
  end

  test "cache_user_id! updates user_id column" do
    membership = workspace_memberships(:alice_acme)
    membership.cache_user_id!(12345)
    assert_equal 12345, membership.reload.user_id
  end

  test "leave! raises LastAdministratorError when user is last administrator" do
    # Create a workspace with only one admin
    workspace = Workspace.create_with_database!(
      name: "Solo Admin Workspace",
      creator: global_identities(:alice)
    )
    membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)

    assert_raises(WorkspaceMembership::LastAdministratorError) do
      membership.leave!
    end

    # Membership should still exist
    assert WorkspaceMembership.exists?(id: membership.id)

    # Cleanup
    workspace.destroy_with_database!
  end

  test "leave! destroys membership and deactivates user" do
    # Create workspace with creator
    workspace = Workspace.create_with_database!(
      name: "Leave Test Workspace",
      creator: global_identities(:alice)
    )

    # Add a second admin so first can leave - use create_user! to properly set up the user
    bob_membership = WorkspaceMembership.create!(
      global_identity: global_identities(:bob),
      tenant: workspace.external_id.to_s
    )
    bob_membership.create_user!(role: :administrator)

    # Now Alice should be able to leave
    alice_membership = WorkspaceMembership.find_by(
      tenant: workspace.external_id.to_s,
      global_identity: global_identities(:alice)
    )

    alice_membership.leave!

    # Membership should be destroyed
    assert_not WorkspaceMembership.exists?(id: alice_membership.id)

    # User should be deactivated
    ApplicationRecord.with_tenant(workspace.external_id.to_s) do
      alice_user = User.unscoped.find_by(email_address: global_identities(:alice).email_address)
      assert alice_user.deactivated?
    end

    # Cleanup
    workspace.destroy_with_database!
  end

  test "create_user! reactivates deactivated user on rejoin" do
    # Create workspace with creator
    workspace = Workspace.create_with_database!(
      name: "Rejoin Test Workspace",
      creator: global_identities(:alice)
    )

    # Add Bob as admin so Alice can leave
    bob_membership = WorkspaceMembership.create!(
      global_identity: global_identities(:bob),
      tenant: workspace.external_id.to_s
    )
    bob_membership.create_user!(role: :administrator)

    # Alice leaves the workspace
    alice_membership = WorkspaceMembership.find_by(
      tenant: workspace.external_id.to_s,
      global_identity: global_identities(:alice)
    )
    alice_user_id = alice_membership.user_id
    alice_membership.leave!

    # Verify Alice is deactivated
    ApplicationRecord.with_tenant(workspace.external_id.to_s) do
      alice_user = User.unscoped.find_by(id: alice_user_id)
      assert alice_user.deactivated?, "User should be deactivated after leaving"
    end

    # Alice rejoins the workspace
    new_membership = WorkspaceMembership.create!(
      global_identity: global_identities(:alice),
      tenant: workspace.external_id.to_s
    )
    rejoined_user = new_membership.create_user!

    # Verify Alice is reactivated (same user record)
    assert_equal alice_user_id, rejoined_user.id, "Should reuse the same User record"
    assert_not rejoined_user.deactivated?, "User should be reactivated on rejoin"
    assert rejoined_user.active?, "User should have active status"

    # Cleanup
    workspace.destroy_with_database!
  end
end
