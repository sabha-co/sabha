# frozen_string_literal: true

require_relative "../../test_helper"

class Admin::IdentitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_global_identity(global_identities(:superadmin))
  end

  test "index requires authentication" do
    delete session_path
    get admin_identities_path
    assert_redirected_to new_session_path
  end

  test "index returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    get admin_identities_path
    assert_response :forbidden
  end

  test "index renders identity list" do
    get admin_identities_path
    assert_response :success
    assert_select "td", text: /alice@example\.com/
  end

  test "index filters by email" do
    get admin_identities_path, params: { query: "alice" }
    assert_response :success
    assert_select "td", text: /alice@example\.com/
    assert_select "td", text: /bob@example\.com/, count: 0
  end

  test "index filters by name" do
    get admin_identities_path, params: { query: "Bob" }
    assert_response :success
    assert_select "td", text: /bob@example\.com/
    assert_select "td", text: /alice@example\.com/, count: 0
  end

  test "index shows workspace count" do
    get admin_identities_path
    assert_response :success
  end

  test "show renders identity details" do
    identity = global_identities(:alice)
    get admin_identity_path(identity)
    assert_response :success
    assert_select "h1", text: /alice@example\.com/
  end

  test "show lists workspaces" do
    identity = global_identities(:alice)
    get admin_identity_path(identity)
    assert_response :success
    assert_select "td", text: /Acme Corp/
  end

  test "show returns 403 for non-superadmin" do
    delete session_path
    sign_in_global_identity(global_identities(:alice))
    get admin_identity_path(global_identities(:alice))
    assert_response :forbidden
  end

  test "index sorts by email ascending" do
    get admin_identities_path, params: { sort: "email_address", direction: "asc" }
    assert_response :success
  end

  test "index sorts by workspaces count" do
    get admin_identities_path, params: { sort: "workspaces_count", direction: "desc" }
    assert_response :success
  end

  test "index sorts by last active" do
    get admin_identities_path, params: { sort: "last_active", direction: "desc" }
    assert_response :success
  end

  test "index ignores invalid sort column" do
    get admin_identities_path, params: { sort: "malicious", direction: "asc" }
    assert_response :success
  end
end
