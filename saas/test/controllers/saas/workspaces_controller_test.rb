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
      assert_redirected_to workspace_path(workspace)
    end

    test "create adds creator as workspace member" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      post workspaces_path, params: { name: "My New Workspace" }

      workspace = Workspace.last
      assert identity.workspace_memberships.exists?(tenant: workspace.external_id.to_s)
    end

    test "show requires authentication" do
      get workspace_path(workspaces(:acme))
      assert_redirected_to new_session_path
    end

    test "show displays provisioning page for own workspace" do
      sign_in_global_identity(global_identities(:alice))
      get workspace_path(workspaces(:acme))
      assert_response :success
    end

    test "show rejects access to other users workspace" do
      sign_in_global_identity(global_identities(:alice))
      assert_raises(ActiveRecord::RecordNotFound) do
        get workspace_path(workspaces(:widgets))
      end
    end

    test "create with invalid name shows error" do
      sign_in_global_identity(global_identities(:alice))

      assert_no_difference "Workspace.count" do
        post workspaces_path, params: { name: "" }
      end

      assert_response :unprocessable_entity
    end
  end
end
