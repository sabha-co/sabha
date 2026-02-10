# frozen_string_literal: true

require_relative "../test_helper"

class SaasCleanupUnverifiedUsersJobTest < ActiveJob::TestCase
  setup do
    @workspace = Workspace.create_with_database!(
      name: "Cleanup Test",
      creator: global_identities(:alice)
    )
    @tenant_id = @workspace.external_id.to_s
  end

  teardown do
    @workspace&.destroy_with_database! if Workspace.exists?(id: @workspace&.id)
  end

  test "clears WorkspaceMembership user_id when deleting orphaned tenant User" do
    # Create a membership and unverified user in the tenant DB
    membership = global_identities(:bob).workspace_memberships.find_or_create_by!(tenant: @tenant_id)

    ApplicationRecord.with_tenant(@tenant_id) do
      user = User.create!(
        name: "Unverified Bob",
        email_address: "bob@example.com",
        workspace_membership_id: membership.id,
        created_at: 2.hours.ago
      )
      membership.cache_user_id!(user.id)
    end

    assert membership.reload.user_id.present?

    CleanupUnverifiedUsersJob.perform_now

    # WorkspaceMembership.user_id should be cleared
    assert_nil membership.reload.user_id

    # User should be deleted from tenant DB
    ApplicationRecord.with_tenant(@tenant_id) do
      assert_equal 1, User.count, "Only the admin user should remain"
    end
  end
end
