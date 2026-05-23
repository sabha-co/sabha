# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class WorkspaceSettingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @workspace = Workspace.create_with_database!(
        name: "Test Workspace",
        creator: global_identities(:alice)
      )
      @session = sign_in_global_identity(global_identities(:alice))
    end

    teardown do
      @workspace&.destroy_with_database! if Workspace.exists?(id: @workspace&.id)
    end

    test "show requires authentication" do
      # Use a fresh workspace without signing in
      other_workspace = Workspace.create_with_database!(
        name: "Auth Test Workspace",
        creator: global_identities(:bob)
      )

      # Clear cookies and make request without signing in
      reset!

      workspace_get "/settings", workspace: other_workspace
      assert_redirected_to "/session/new"

      other_workspace.destroy_with_database!
    end

    test "show displays workspace info" do
      workspace_get "/settings", workspace: @workspace

      assert_response :success
      assert_select "h1", @workspace.name
      # Admin view exposes Storage and Delete workspace sections
      assert_select "h2", text: /Storage/
      assert_select "h2", text: /Delete workspace/
      # Header shows member count
      assert_select "p", text: /1 member/
    end
  end
end
