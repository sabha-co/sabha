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

  test "index sorts by name ascending" do
    get admin_workspaces_path, params: { sort: "name", direction: "asc" }
    assert_response :success
    names = controller.instance_variable_get(:@workspaces).map(&:name)
    assert_equal names.sort, names
  end

  test "index sorts by last active" do
    get admin_workspaces_path, params: { sort: "last_active", direction: "desc" }
    assert_response :success
    timestamps = controller.instance_variable_get(:@workspaces).map(&:last_active_at)
    non_nil = timestamps.compact
    assert_equal non_nil.sort.reverse, non_nil
    # DESC NULLS LAST: any nils must be at the tail
    nils = timestamps.size - non_nil.size
    assert_equal nils, timestamps.last(nils).count(&:nil?) if nils > 0
  end

  test "index sorts by members count" do
    get admin_workspaces_path, params: { sort: "members_count", direction: "desc" }
    assert_response :success
    counts = controller.instance_variable_get(:@workspaces).map { |w| w.members_count.to_i }
    assert_equal counts.sort.reverse, counts
  end

  test "index sorts by db size" do
    get admin_workspaces_path, params: { sort: "db_size", direction: "desc" }
    assert_response :success
    sizes = controller.instance_variable_get(:@workspaces).map(&:snapshot_database_size)
    non_nil = sizes.compact
    assert_equal non_nil.sort.reverse, non_nil
    nils = sizes.size - non_nil.size
    assert_equal nils, sizes.last(nils).count(&:nil?) if nils > 0
  end

  test "index ignores invalid sort column" do
    get admin_workspaces_path, params: { sort: "drop_table", direction: "asc" }
    assert_response :success
    invalid_sort_ids = controller.instance_variable_get(:@workspaces).map(&:id)

    get admin_workspaces_path
    default_sort_ids = controller.instance_variable_get(:@workspaces).map(&:id)

    assert_equal default_sort_ids, invalid_sort_ids
  end
end
