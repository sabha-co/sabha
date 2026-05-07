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
    with_provisioned_workspace(name: "Account Name Test", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)
      assert_equal "Account Name Test", membership.account_name
    end
  end

  test "account_name returns nil when tenant does not exist" do
    # Use a tenant ID that is guaranteed to never have a database
    membership = WorkspaceMembership.create!(
      global_identity: global_identities(:alice),
      tenant: "9999999"
    )
    assert_nil membership.account_name
  ensure
    membership&.destroy
  end

  test "cache_user_id! updates user_id column" do
    membership = workspace_memberships(:alice_acme)
    membership.cache_user_id!(12345)
    assert_equal 12345, membership.reload.user_id
  end

  test "leave! raises LastAdministratorError when user is last administrator" do
    with_provisioned_workspace(name: "Solo Admin Workspace", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)

      assert_raises(WorkspaceMembership::LastAdministratorError) do
        membership.leave!
      end

      # Membership should still exist
      assert WorkspaceMembership.exists?(id: membership.id)
    end
  end

  test "leave! destroys membership and deactivates user" do
    with_provisioned_workspace(name: "Leave Test Workspace", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :administrator)

      alice_membership = WorkspaceMembership.find_by(
        tenant: workspace.external_id.to_s,
        global_identity: global_identities(:alice)
      )

      alice_membership.leave!

      assert_not WorkspaceMembership.exists?(id: alice_membership.id)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        alice_user = User.unscoped.find_by(email_address: global_identities(:alice).email_address)
        assert alice_user.deactivated?
      end
    end
  end

  test "create_user! reactivates deactivated user on rejoin" do
    with_provisioned_workspace(name: "Rejoin Test Workspace", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :administrator)

      alice_membership = WorkspaceMembership.find_by(
        tenant: workspace.external_id.to_s,
        global_identity: global_identities(:alice)
      )
      alice_user_id = alice_membership.user_id
      alice_membership.leave!

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        alice_user = User.unscoped.find_by(id: alice_user_id)
        assert alice_user.deactivated?, "User should be deactivated after leaving"
      end

      new_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:alice),
        tenant: workspace.external_id.to_s
      )
      rejoined_user = new_membership.create_user!

      assert_equal alice_user_id, rejoined_user.id, "Should reuse the same User record"
      assert_not rejoined_user.deactivated?, "User should be reactivated on rejoin"
      assert rejoined_user.active?, "User should have active status"
    end
  end

  test "User#unban flips workspace_memberships.user_active back to true" do
    with_provisioned_workspace(name: "Unban Mirror Test", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).ban
      end
      assert_not membership.reload.user_active, "ban must mirror to user_active=false"

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).unban
      end
      assert membership.reload.user_active, "unban must mirror to user_active=true"
    end
  end

  test "User#reactivate flips workspace_memberships.user_active back to true" do
    with_provisioned_workspace(name: "Reactivate Mirror Test", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).deactivate
      end
      assert_not membership.reload.user_active, "deactivate must mirror to user_active=false"

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).reactivate
      end
      assert membership.reload.user_active, "reactivate must mirror to user_active=true"
    end
  end

  test "User hard-destroy flips workspace_memberships.user_active to false so the workspace selector hides the orphan" do
    with_provisioned_workspace(name: "Hard Destroy Test", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)
      assert membership.user_active, "precondition: membership starts active"

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).destroy!
      end

      membership.reload
      assert_nil membership.user_id, "destroy must clear cached user_id"
      assert_not membership.user_active, "destroy must drop the user_active mirror"
      assert_not_includes global_identities(:alice).active_workspaces_recent_first, workspace,
        "workspace selector must not surface the orphaned membership"
    end
  end

  test "create_user! after a hard-destroy restores user_active so the workspace becomes reachable again" do
    with_provisioned_workspace(name: "Recreate After Destroy", creator: global_identities(:alice)) do |workspace|
      membership = WorkspaceMembership.find_by(tenant: workspace.external_id.to_s)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).destroy!
      end
      assert_not membership.reload.user_active

      membership.create_user!

      assert membership.reload.user_active,
        "after_create_commit must re-flip user_active=true when a new User is provisioned"
    end
  end
end
