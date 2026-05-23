# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::SnapshotJobTest < ActiveSupport::TestCase
  test "creates snapshot for workspace with provisioned database" do
    creator = global_identities(:admin)

    with_provisioned_workspace(name: "Snapshot Test", creator: creator) do |workspace|
      # Clean up any stale messages from tenant DB reuse. destroy_all (not
      # delete_all) so Message#destroy_all_associated_records cascades to
      # notifications/boosts/bookmarks — otherwise the FK constraint trips.
      ApplicationRecord.with_tenant(workspace.external_id.to_s) { Message.destroy_all }

      Workspace::SnapshotJob.perform_now(workspace)

      snapshot = workspace.reload.snapshot
      assert_not_nil snapshot
      assert_equal 0, snapshot.messages_7d
      assert_equal 1, snapshot.active_users
      assert snapshot.database_size > 0
    end
  end

  test "handles missing tenant database gracefully" do
    # Create a workspace record and drop any stale tenant DB (the external_id
    # sequence rolls back between tests, so the on-disk SQLite may already
    # exist from a prior test). The missing-tenant state is what
    # `discard_on TenantDoesNotExistError` exists to swallow.
    workspace = Workspace.create!(name: "No Tenant DB", creator: global_identities(:admin))
    tenant_id = workspace.external_id.to_s
    ApplicationRecord.destroy_tenant(tenant_id) if ApplicationRecord.tenant_exist?(tenant_id)
    assert_not ApplicationRecord.tenant_exist?(tenant_id)

    # discard_on TenantDoesNotExistError → no exception escapes, no snapshot row created.
    Workspace::SnapshotJob.perform_now(workspace)

    assert_nil workspace.reload.snapshot
  end
end
