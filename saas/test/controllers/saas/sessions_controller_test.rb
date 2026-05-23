# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    test "new renders login form" do
      get new_session_path
      assert_response :success
    end

    test "new stores return_to param in session" do
      get new_session_path, params: { return_to: "/1000001/rooms/general" }
      assert_response :success
      assert_equal "/1000001/rooms/general", session[:return_to_after_authenticating]
    end

    test "create sends auth code for existing identity" do
      identity = global_identities(:alice)

      assert_enqueued_emails 1 do
        post session_path, params: { email_address: identity.email_address }
      end

      assert_redirected_to auth_code_path
      # Same message shown whether email exists or not (prevents email enumeration)
      assert_equal "If this email is registered, you'll receive a sign-in code", flash[:notice]
    end

    test "create does not create identity for unknown email (prevents enumeration)" do
      # Login should NOT create new identities - that's what registration is for
      assert_no_difference "GlobalIdentity.count" do
        assert_no_enqueued_emails do
          post session_path, params: { email_address: "unknown@example.com" }
        end
      end

      assert_redirected_to auth_code_path
      # Same message shown whether email exists or not (prevents email enumeration)
      assert_equal "If this email is registered, you'll receive a sign-in code", flash[:notice]
    end

    test "create normalizes email when looking up identity" do
      # Create identity with normalized email
      identity = global_identities(:alice)

      # Login with mixed case should find the existing identity
      assert_enqueued_emails 1 do
        post session_path, params: { email_address: "  #{identity.email_address.upcase}  " }
      end
    end

    test "create creates auth code with sign_in purpose" do
      identity = global_identities(:alice)

      assert_difference "AuthCode.count", 1 do
        post session_path, params: { email_address: identity.email_address }
      end

      code = AuthCode.last
      assert_equal identity, code.global_identity
      assert code.sign_in?
    end

    test "destroy signs out and redirects" do
      sign_in_global_identity(global_identities(:alice))

      delete session_path

      assert_redirected_to new_session_path
      assert_equal "You have been signed out", flash[:notice]
    end

    test "new redirects authenticated user" do
      sign_in_global_identity(global_identities(:alice))

      get new_session_path

      # Should redirect away from login page
      assert_response :redirect
    end
  end
end
