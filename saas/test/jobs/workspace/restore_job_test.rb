# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::RestoreJobTest < ActiveSupport::TestCase
  test "downloads backup from R2 and replaces tenant database" do
    with_provisioned_workspace(name: "Restore Test", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")

      # Add a user we expect to survive the restore
      ApplicationRecord.with_tenant(tenant_id) do
        User.create!(name: "Before Restore", email_address: "before@example.com", password: "password123456")
      end

      # Snapshot the DB at this point — this becomes our "backup"
      backup_copy = Tempfile.new([ "restore-test", ".sqlite3" ])
      source_db = SQLite3::Database.new(db_path.to_s)
      dest_db = SQLite3::Database.new(backup_copy.path)
      sqlite_backup = SQLite3::Backup.new(dest_db, "main", source_db, "main")
      sqlite_backup.step(-1)
      sqlite_backup.finish
      source_db.close
      dest_db.close

      # Add another user after the snapshot — this should disappear after restore
      ApplicationRecord.with_tenant(tenant_id) do
        User.create!(name: "After Backup", email_address: "after@example.com", password: "password123456")
        assert User.exists?(email_address: "after@example.com")
      end

      backup = workspace.backups.create!(key: "backups/#{workspace.external_id}/test.sqlite3", size: 1024)

      s3_client = stub
      s3_client.stubs(:get_object).with do |params|
        FileUtils.cp(backup_copy.path, params[:response_target])
        true
      end
      s3_client.stubs(:delete_object)
      Workspace::Backup.stubs(:s3_client).returns(s3_client)

      Workspace::RestoreJob.perform_now(workspace, backup)

      # Verify workspace was unsuspended after restore
      workspace.reload
      assert_not workspace.suspended?, "Workspace should be unsuspended after successful restore"

      # Verify the restored DB has the pre-backup user but not the post-backup one
      ApplicationRecord.with_tenant(tenant_id) do
        assert User.exists?(email_address: "before@example.com")
        assert_not User.exists?(email_address: "after@example.com")
      end
    ensure
      backup_copy&.unlink
    end
  end

  test "preserves suspension state if workspace was already suspended" do
    with_provisioned_workspace(name: "Suspended Restore Test", creator: global_identities(:alice)) do |workspace|
      workspace.suspend!
      backup = workspace.backups.create!(key: "backups/#{workspace.external_id}/test.sqlite3", size: 1024)

      tenant_id = workspace.external_id.to_s
      db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")

      s3_client = stub
      s3_client.stubs(:get_object).with do |params|
        FileUtils.cp(db_path.to_s, params[:response_target])
        true
      end
      s3_client.stubs(:delete_object)
      Workspace::Backup.stubs(:s3_client).returns(s3_client)

      Workspace::RestoreJob.perform_now(workspace, backup)

      workspace.reload
      assert workspace.suspended?, "Workspace should remain suspended if it was suspended before restore"
    end
  end

  test "cleans up staging file on failure" do
    with_provisioned_workspace(name: "Restore Fail Test", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")
      staging_path = "#{db_path}.restoring"

      backup = workspace.backups.create!(key: "backups/#{workspace.external_id}/fail.sqlite3", size: 1024)

      s3_client = stub
      s3_client.stubs(:get_object).raises(Aws::S3::Errors::NoSuchKey.new(nil, "not found"))
      s3_client.stubs(:delete_object)
      Workspace::Backup.stubs(:s3_client).returns(s3_client)

      assert_raises(Aws::S3::Errors::NoSuchKey) do
        Workspace::RestoreJob.perform_now(workspace, backup)
      end

      assert_not File.exist?(staging_path), "Staging file should be cleaned up after failure"
    end
  end
end
