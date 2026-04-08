# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::SnapshotJobTest < ActiveSupport::TestCase
  test "creates snapshot for workspace with provisioned database" do
    creator = global_identities(:admin)

    with_provisioned_workspace(name: "Snapshot Test", creator: creator) do |workspace|
      # Clean up any stale messages from tenant DB reuse
      ApplicationRecord.with_tenant(workspace.external_id.to_s) { Message.delete_all }

      Workspace::SnapshotJob.perform_now(workspace)

      snapshot = workspace.reload.snapshot
      assert_not_nil snapshot
      assert_equal 0, snapshot.messages_7d
      assert_equal 1, snapshot.active_users
      assert snapshot.database_size > 0
    end
  end

  test "handles missing tenant database gracefully" do
    workspace = workspaces(:acme)

    # Should not raise — tenant DB doesn't exist in test fixtures
    assert_nothing_raised do
      Workspace::SnapshotJob.perform_now(workspace)
    end
  end
end
