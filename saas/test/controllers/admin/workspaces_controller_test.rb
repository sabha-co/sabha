# frozen_string_literal: true

require_relative "../../test_helper"

class Admin::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_global_identity(global_identities(:superadmin))
  end

  test "index requires authentication" do
    delete session_path
    get admin_workspaces_path
    assert_redirected_to new_session_path
  end

  test "index returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    get admin_workspaces_path
    assert_response :forbidden
  end

  test "index renders workspace list" do
    get admin_workspaces_path
    assert_response :success
    assert_select "td", text: /Acme Corp/
  end

  test "index filters by query" do
    get admin_workspaces_path, params: { query: "Acme" }
    assert_response :success
    assert_select "td", text: /Acme Corp/
    assert_select "td", text: /Widgets Inc/, count: 0
  end

  test "show renders workspace details" do
    workspace = workspaces(:acme)
    get admin_workspace_path(workspace)
    assert_response :success
    assert_select "h1", text: /Acme Corp/
  end

  test "show returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    get admin_workspace_path(workspaces(:acme))
    assert_response :forbidden
  end
end
