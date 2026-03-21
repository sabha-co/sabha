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

      # Flush WAL to main database file before snapshotting
      ApplicationRecord.with_tenant(tenant_id) do
        ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
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

      fake_s3 = Class.new do
        define_method(:get_object) do |bucket:, key:, response_target:|
          FileUtils.cp(backup_copy.path, response_target)
        end
        def delete_object(...) = nil
      end.new
      Workspace::Backup.stubs(:s3_client).returns(fake_s3)

      Workspace::RestoreJob.perform_now(workspace, backup)

      # The restore job drops the connection pool. Verify the new DB by
      # opening a fresh connection directly to avoid any stale pool state.
      restored_db = SQLite3::Database.new(db_path.to_s)
      users = restored_db.execute("SELECT email_address FROM users")
      restored_db.close

      emails = users.flatten
      assert_includes emails, "before@example.com"
      assert_not_includes emails, "after@example.com"
    ensure
      backup_copy&.unlink
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
