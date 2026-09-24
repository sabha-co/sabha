# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class LandingControllerTest < ActionDispatch::IntegrationTest
    test "show renders landing page for unauthenticated users" do
      get root_path
      assert_response :success
    end

    test "show redirects authenticated users to most recent workspace" do
      sign_in_global_identity(global_identities(:alice))
      get root_path
      # Redirects directly to most recently accessed workspace
      most_recent = global_identities(:alice).active_workspaces_recent_first.first
      assert_redirected_to "/#{most_recent.external_id}"
    end

    test "show redirects authenticated user with no workspaces to create" do
      sign_in_global_identity(global_identities(:unverified))
      get root_path
      assert_redirected_to new_workspace_path
    end

    test "desktop client does not render the marketing landing" do
      get root_path, headers: { "Sabha-Client" => "desktop" }

      assert_redirected_to new_session_path
    end

    test "signed-in desktop client skips marketing landing for a workspace" do
      sign_in_global_identity(global_identities(:alice))
      get root_path, headers: { "Sabha-Client" => "desktop" }

      most_recent = global_identities(:alice).active_workspaces_recent_first.first
      assert_redirected_to "/#{most_recent.external_id}"
    end

    test "desktop client does not render about marketing" do
      get about_path, headers: { "Sabha-Client" => "desktop" }

      assert_redirected_to new_session_path
    end
  end
end
