# frozen_string_literal: true

require_relative "../../test_helper"

class Admin::WorkspaceBackupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_global_identity(global_identities(:superadmin))
    @workspace = workspaces(:acme)
  end

  test "index renders backup list" do
    get admin_workspace_backups_path(@workspace)
    assert_response :success
    assert_select "h1", text: /Backups/
  end

  test "index returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    get admin_workspace_backups_path(@workspace)
    assert_response :forbidden
  end

  test "create enqueues backup job" do
    Workspace::Backup.stubs(:r2_configured?).returns(true)

    assert_enqueued_with(job: Workspace::BackupJob, args: [ @workspace ]) do
      post admin_workspace_backups_path(@workspace)
    end
    assert_redirected_to admin_workspace_backups_path(@workspace)
  end

  test "create returns alert when R2 is not configured" do
    Workspace::Backup.stubs(:r2_configured?).returns(false)

    assert_no_enqueued_jobs do
      post admin_workspace_backups_path(@workspace)
    end
    assert_redirected_to admin_workspace_backups_path(@workspace)
    assert_equal "Backups are not configured. Set R2 credentials to enable.", flash[:alert]
  end

  test "restore enqueues restore job" do
    backup = Workspace::Backup.create!(workspace: @workspace, key: "backups/test.sqlite3", size: 1024)

    assert_enqueued_with(job: Workspace::RestoreJob, args: [ @workspace, backup ]) do
      post admin_workspace_backup_restore_path(@workspace, backup)
    end
    assert_redirected_to admin_workspace_backups_path(@workspace)
  end
end
