# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::BackupJobTest < ActiveSupport::TestCase
  test "creates backup record and uploads to R2" do
    with_provisioned_workspace(name: "Backup Test", creator: global_identities(:alice)) do |workspace|
      Workspace::R2.stubs(:configured?).returns(true)

      s3_client = stub
      s3_client.stubs(:put_object)
      s3_client.stubs(:delete_object)
      Workspace::R2.stubs(:client).returns(s3_client)

      Workspace::BackupJob.perform_now(workspace)

      assert_equal 1, workspace.backups.count
      backup = workspace.backups.first
      assert_match /\Abackups\/#{workspace.external_id}\/\d{14}-[0-9a-f]{8}\.sqlite3\z/, backup.key
      assert backup.size > 0
    end
  end

  test "cleans up expired backups after creating new one" do
    with_provisioned_workspace(name: "Cleanup Test", creator: global_identities(:alice)) do |workspace|
      old_backup = workspace.backups.create!(key: "backups/old.sqlite3", size: 1024, created_at: 8.days.ago)

      Workspace::R2.stubs(:configured?).returns(true)

      s3_client = stub
      s3_client.stubs(:put_object)
      s3_client.stubs(:delete_object)
      Workspace::R2.stubs(:client).returns(s3_client)

      Workspace::BackupJob.perform_now(workspace)

      assert_not Workspace::Backup.exists?(id: old_backup.id)
      assert_equal 1, workspace.backups.count
    end
  end
end
