# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class AuthenticationTest < ActionDispatch::IntegrationTest
    test "expired GlobalSession is rejected by active scope" do
      session = global_sessions(:expired_session)

      assert session.expired?
      assert_not_includes GlobalSession.active, session
    end

    test "expired session cookie is cleared on request" do
      session = global_sessions(:expired_session)
      cookies[:global_session_token] = session.token

      get workspaces_path

      # Should redirect to login (session invalid)
      assert_redirected_to new_session_path
    end

    test "valid session cookie authenticates user" do
      # Use the helper that properly sets up session
      sign_in_global_identity(global_identities(:alice))

      get settings_path

      # Should be able to access authenticated page
      assert_response :success
    end

    test "sign_in creates session and sets cookie" do
      identity = global_identities(:alice)
      code = auth_codes(:alice_signin)

      assert_difference "GlobalSession.count", 1 do
        post auth_code_path, params: { code: code.code }
      end

      # Cookie should be set
      assert cookies[:global_session_token].present?

      # New session should be associated with the identity
      new_session = GlobalSession.last
      assert_equal identity, new_session.global_identity
    end

    test "sign_out destroys session and clears cookie" do
      sign_in_global_identity(global_identities(:alice))
      session_count_before = GlobalSession.count

      delete session_path

      # Session should be destroyed
      assert_equal session_count_before - 1, GlobalSession.count

      # Should redirect to login
      assert_redirected_to new_session_path
    end

    test "after_authentication_url stores return_to param" do
      workspace = workspaces(:acme)

      # Visiting auth_code_path with return_to param stores it in session
      get auth_code_path, params: { return_to: "/#{workspace.external_id}/rooms/general" }

      assert_equal "/#{workspace.external_id}/rooms/general", session[:return_to_after_authenticating]
    end

    test "after_authentication_url defaults to root when no return_to" do
      code = auth_codes(:alice_signin)

      post auth_code_path, params: { code: code.code }

      # Should redirect to root (workspace selector)
      assert_redirected_to "/"
    end

    test "require_authentication redirects unauthenticated users" do
      get workspaces_path

      assert_redirected_to new_session_path
      assert_equal "Please sign in to continue", flash[:alert]
    end

    test "require_authentication stores current URL for redirect" do
      get workspaces_path

      assert_redirected_to new_session_path
      assert_equal "/workspaces", session[:return_to_after_authenticating]
    end

    test "user whose tenant User was deleted gets it recreated on next visit" do
      workspace = Workspace.create_with_database!(name: "Orphan Test", creator: global_identities(:alice))
      sign_in_global_identity(global_identities(:alice))
      membership = global_identities(:alice).workspace_memberships.find_by(tenant: workspace.external_id.to_s)

      # Delete the User from the tenant DB (simulates CleanupUnverifiedUsersJob)
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(membership.user_id).destroy!
      end

      # Visit the workspace — should recreate the User, not crash or redirect loop
      workspace_get "/", workspace: workspace

      # WelcomeController redirects to landing room on success — no error, no loop
      assert_response :redirect
      assert_not_equal "/workspaces", response.location # not bounced to workspace selector

      # User was recreated
      membership.reload
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        assert User.exists?(id: membership.user_id)
      end
    ensure
      workspace&.destroy_with_database! if workspace && Workspace.exists?(id: workspace.id)
    end

    test "authenticated user accessing workspace they are not a member of is redirected to workspace selector" do
      # Bob is NOT a member of acme workspace
      sign_in_global_identity(global_identities(:bob))

      workspace_get "/", workspace: workspaces(:acme)

      assert_redirected_to "/workspaces"
    end

    test "require_unauthenticated_access redirects authenticated users" do
      sign_in_global_identity(global_identities(:alice))

      get new_session_path

      # Should redirect away from login page
      assert_response :redirect
    end
  end
end
