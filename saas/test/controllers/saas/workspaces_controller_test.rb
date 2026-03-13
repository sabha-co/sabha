# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class WorkspacesControllerTest < ActionDispatch::IntegrationTest
    test "index requires authentication" do
      get workspaces_path
      assert_redirected_to new_session_path
    end

    test "index redirects to most recent workspace" do
      sign_in_global_identity(global_identities(:alice))
      get workspaces_path
      # Redirects to most recently accessed workspace (by membership updated_at)
      assert_response :redirect
    end

    test "new requires authentication" do
      get new_workspace_path
      assert_redirected_to new_session_path
    end

    test "new renders form when authenticated" do
      sign_in_global_identity(global_identities(:alice))
      get new_workspace_path
      assert_response :success
    end

    test "create requires authentication" do
      post workspaces_path, params: { name: "New Workspace" }
      assert_redirected_to new_session_path
    end

    test "create success creates workspace and redirects" do
      sign_in_global_identity(global_identities(:alice))

      assert_difference "Workspace.count", 1 do
        post workspaces_path, params: { name: "My New Workspace" }
      end

      workspace = Workspace.last
      assert_equal "My New Workspace", workspace.name
      assert_redirected_to "/#{workspace.external_id}/invite"
      assert_equal "Workspace created!", flash[:notice]
    end

    test "create adds creator as workspace member" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      post workspaces_path, params: { name: "My New Workspace" }

      workspace = Workspace.last
      assert identity.workspace_memberships.exists?(tenant: workspace.external_id.to_s)
    end

    test "create with invalid name shows error" do
      sign_in_global_identity(global_identities(:alice))

      assert_no_difference "Workspace.count" do
        post workspaces_path, params: { name: "" }
      end

      assert_response :unprocessable_entity
    end

    # Join flow tests
    # Note: Join codes are stored in Account model within tenant database,
    # not directly on Workspace. These tests focus on the join controller behavior.

    test "join with invalid code redirects unauthenticated user to login" do
      get join_path(code: "INVALID123")

      assert_redirected_to new_session_path
      assert_match /Invalid or expired/, flash[:alert]
    end

    test "join with invalid code redirects authenticated user to workspaces" do
      sign_in_global_identity(global_identities(:alice))
      get join_path(code: "INVALID123")

      assert_redirected_to workspaces_path
      assert_match /Invalid or expired/, flash[:alert]
    end

    test "join with short code redirects to login" do
      get "/join/AB"

      assert_redirected_to new_session_path
      assert_match /Invalid or expired/, flash[:alert]
    end
  end
end
