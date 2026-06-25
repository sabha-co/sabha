# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class AuthCodesControllerTest < ActionDispatch::IntegrationTest
    test "show renders code entry form" do
      get auth_code_path
      assert_response :success
    end

    test "show stores return_to param in session" do
      get auth_code_path, params: { return_to: "/1000001/rooms" }
      assert_response :success
      assert_equal "/1000001/rooms", session[:return_to_after_authenticating]
    end

    test "create with valid sign_in code shows welcome back" do
      code = auth_codes(:alice_signin)

      post auth_code_path, params: { code: code.code }

      # Redirects to saas_root_path (/) by default
      assert_response :redirect
      assert_equal "Welcome back!", flash[:notice]
    end

    test "create with valid sign_up code shows welcome" do
      code = auth_codes(:unverified_signup)

      post auth_code_path, params: { code: code.code }

      assert_response :redirect
      assert_equal "Welcome!", flash[:notice]
    end

    test "create with valid code verifies unverified identity" do
      identity = global_identities(:unverified)
      code = auth_codes(:unverified_signup)

      assert_not identity.verified?

      post auth_code_path, params: { code: code.code }

      assert identity.reload.verified?
    end

    test "create with valid code consumes the auth code" do
      code = auth_codes(:alice_signin)
      code_value = code.code

      assert_difference "AuthCode.count", -1 do
        post auth_code_path, params: { code: code_value }
      end
    end

    test "create with expired code shows error" do
      code = auth_codes(:expired_code)

      post auth_code_path, params: { code: code.code }

      assert_redirected_to auth_code_path
      assert_match /Invalid or expired/, flash[:alert]
    end

    test "create with email_change code completes email change" do
      identity = global_identities(:pending_email)
      code = auth_codes(:email_change)
      original_email = identity.email_address
      new_email = identity.unconfirmed_email

      assert_equal "pending@example.com", original_email
      assert_equal "newpending@example.com", new_email

      post auth_code_path, params: { code: code.code }

      assert_redirected_to workspaces_path
      assert_match /Email changed from.*to/, flash[:notice]

      identity.reload
      assert_equal new_email, identity.email_address
      assert_nil identity.unconfirmed_email
    end

    test "create with email_change code when no pending email shows alert" do
      identity = global_identities(:alice)
      # Create an email_change code but with no pending email
      code = identity.auth_codes.create!(purpose: :email_change, expires_at: 15.minutes.from_now)

      post auth_code_path, params: { code: code.code }

      assert_redirected_to workspaces_path
      assert_match /No pending email change/, flash[:alert]
    end
  end
end
