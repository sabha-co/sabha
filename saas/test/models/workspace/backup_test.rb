# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::BackupTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:acme)
  end

  test "expired scope returns backups older than retention period" do
    old_backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/old.sqlite3", size: 1024, created_at: 8.days.ago)
    recent_backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/recent.sqlite3", size: 1024, created_at: 1.day.ago)

    expired = Workspace::Backup.expired
    assert_includes expired, old_backup
    assert_not_includes expired, recent_backup
  end

  test "purge_expired! deletes old backups and their R2 objects" do
    old_backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/old.sqlite3", size: 1024, created_at: 8.days.ago)
    recent_backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/recent.sqlite3", size: 1024, created_at: 1.day.ago)

    s3_client = mock
    s3_client.expects(:delete_object).with(bucket: Workspace::R2.bucket, key: "backups/old.sqlite3")
    Workspace::R2.stubs(:client).returns(s3_client)

    Workspace::Backup.purge_expired!

    assert_not Workspace::Backup.exists?(id: old_backup.id)
    assert Workspace::Backup.exists?(id: recent_backup.id)
  end

  test "purge! handles NoSuchKey gracefully" do
    backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/missing.sqlite3", size: 1024, created_at: 8.days.ago)

    s3_client = mock
    s3_client.expects(:delete_object).raises(Aws::S3::Errors::NoSuchKey.new(nil, "not found"))
    Workspace::R2.stubs(:client).returns(s3_client)

    backup.purge!

    assert_not Workspace::Backup.exists?(id: backup.id)
  end
end
