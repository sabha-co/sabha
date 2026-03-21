# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::BackupJobTest < ActiveSupport::TestCase
  test "creates backup record and uploads to R2" do
    with_provisioned_workspace(name: "Backup Test", creator: global_identities(:alice)) do |workspace|
      s3_client = mock
      s3_client.expects(:put_object).with(
        bucket: Workspace::Backup.bucket,
        key: regexp_matches(/\Abackups\/#{workspace.external_id}\/\d{14}-[0-9a-f]{8}\.sqlite3\z/),
        body: anything
      ).once
      s3_client.stubs(:delete_object)
      Workspace::Backup.stubs(:s3_client).returns(s3_client)

      Workspace::BackupJob.perform_now(workspace)

      assert_equal 1, workspace.backups.count
      backup = workspace.backups.first
      assert backup.key.start_with?("backups/#{workspace.external_id}/")
      assert backup.size > 0
    end
  end

  test "cleans up expired backups after creating new one" do
    with_provisioned_workspace(name: "Cleanup Test", creator: global_identities(:alice)) do |workspace|
      old_backup = workspace.backups.create!(key: "backups/old.sqlite3", size: 1024, created_at: 8.days.ago)

      s3_client = stub
      s3_client.stubs(:put_object)
      s3_client.stubs(:delete_object)
      Workspace::Backup.stubs(:s3_client).returns(s3_client)

      Workspace::BackupJob.perform_now(workspace)

      assert_not Workspace::Backup.exists?(id: old_backup.id)
      assert_equal 1, workspace.backups.count
    end
  end
end
