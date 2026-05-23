# frozen_string_literal: true

require_relative "../../test_helper"

class Admin::StatsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "returns 403 for non-superadmin" do
    sign_in_global_identity(global_identities(:alice))
    get admin_root_path
    assert_response :forbidden
  end

  test "renders stats for superadmin" do
    sign_in_global_identity(global_identities(:superadmin))
    get admin_root_path
    assert_response :success
    # Workspace stat tiles include a Total card with the actual workspace count
    assert_select "h2", text: /Workspaces/
    assert_select "div", text: Workspace.count.to_s
    assert_select "h2", text: /Identities/
    # Recent workspaces/signups tables render
    assert_select "section h2", text: /Recent Workspaces/
    assert_select "section h2", text: /Recent Signups/
  end
end
