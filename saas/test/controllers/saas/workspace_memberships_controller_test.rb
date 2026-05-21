# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class WorkspaceMembershipsControllerTest < ActionDispatch::IntegrationTest
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

    test "leave as last admin returns error" do
      workspace_delete "/membership", workspace: @workspace

      assert_redirected_to "/#{@workspace.external_id}/settings"
      assert_equal "You cannot leave as the last administrator.", flash[:alert]
    end

    test "leave as non-last-admin succeeds" do
      # Add a second admin using create_user! for proper setup
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: @workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :administrator)

      workspace_delete "/membership", workspace: @workspace

      assert_redirected_to workspaces_url(script_name: "")
      assert_match /left/, flash[:notice]
    end

    test "leave returns 404 when not a member" do
      # Sign in as someone who isn't a member of this workspace
      sign_in_global_identity(global_identities(:bob))

      workspace_delete "/membership", workspace: @workspace

      assert_response :not_found
    end
  end
end
