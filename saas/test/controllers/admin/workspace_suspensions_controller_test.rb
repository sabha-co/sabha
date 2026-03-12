# frozen_string_literal: true

require_relative "../../test_helper"

class Admin::WorkspaceSuspensionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_global_identity(global_identities(:superadmin))
  end

  test "create suspends an active workspace" do
    workspace = workspaces(:acme)
    assert workspace.active?

    post admin_workspace_suspension_path(workspace)

    assert_redirected_to admin_workspace_path(workspace)
    assert workspace.reload.suspended?
  end

  test "destroy unsuspends a suspended workspace" do
    workspace = workspaces(:suspended)
    assert workspace.suspended?

    delete admin_workspace_suspension_path(workspace)

    assert_redirected_to admin_workspace_path(workspace)
    assert workspace.reload.active?
  end

  test "create returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    post admin_workspace_suspension_path(workspaces(:acme))
    assert_response :forbidden
  end
end
