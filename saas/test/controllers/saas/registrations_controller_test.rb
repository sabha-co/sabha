# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    include TurnstileTestHelper

    test "new renders signup form" do
      get new_registration_path
      assert_response :success
    end

    test "new clears stale return_to when none is supplied" do
      # An earlier, abandoned SSO flow stored a cross-origin return_to.
      get new_registration_path, params: { return_to: "/session/sso?sso=abc&sig=def" }
      assert_equal "/session/sso?sso=abc&sig=def", session[:return_to_after_authenticating]

      # A later plain signup with no return_to must not inherit the stale value.
      get new_registration_path
      assert_nil session[:return_to_after_authenticating]
    end

    test "create with blank email redirects with validation errors" do
      post registration_path, params: with_turnstile_response(name: "Test", email_address: "")
      assert_redirected_to new_registration_path
      assert_match /Email address/, flash[:alert]
    end

    test "create with blank name still succeeds (name is optional, fallback to email prefix)" do
      assert_difference "GlobalIdentity.count", 1 do
        post registration_path, params: with_turnstile_response(name: "", email_address: "noname@example.com", terms_of_service: "1")
      end

      assert_redirected_to auth_code_path
      identity = GlobalIdentity.find_by(email_address: "noname@example.com")
      assert_nil identity.name
    end

    test "create rejects when terms checkbox is unchecked" do
      assert_no_difference "GlobalIdentity.count" do
        post registration_path, params: with_turnstile_response(name: "Test", email_address: "rejecttest@example.com", terms_of_service: "0")
      end

      assert_redirected_to new_registration_path
      assert_match /Terms of service/, flash[:alert]
    end

    test "create with existing email sends sign_in auth code (same message as new)" do
      existing_identity = global_identities(:alice)

      assert_difference "AuthCode.count", 1 do
        assert_enqueued_emails 1 do
          post registration_path, params: with_turnstile_response(name: "Alice", email_address: existing_identity.email_address)
        end
      end

      assert_redirected_to auth_code_path
      # Same message shown whether email exists or not (prevents email enumeration)
      assert_match /Check your email for a verification code/, flash[:notice]

      # Auth code should be for sign_in (existing account gets sign_in, not sign_up)
      auth_code = AuthCode.last
      assert_equal existing_identity, auth_code.global_identity
      assert auth_code.sign_in?
    end

    test "create with new email creates GlobalIdentity and sends sign_up auth code" do
      new_email = "newuser@example.com"

      assert_difference "GlobalIdentity.count", 1 do
        assert_difference "AuthCode.count", 1 do
          assert_enqueued_emails 1 do
            post registration_path, params: with_turnstile_response(name: "New User", email_address: new_email, terms_of_service: "1")
          end
        end
      end

      assert_redirected_to auth_code_path
      assert_match /Check your email for a verification code/, flash[:notice]

      # GlobalIdentity should be created with name
      identity = GlobalIdentity.find_by(email_address: new_email)
      assert identity.present?
      assert_equal "New User", identity.name
      assert_nil identity.verified_at

      # Auth code should be for sign_up
      auth_code = AuthCode.last
      assert_equal identity, auth_code.global_identity
      assert auth_code.sign_up?
    end

    test "create normalizes email to lowercase" do
      post registration_path, params: with_turnstile_response(name: "New User", email_address: "  NewUser@Example.COM  ", terms_of_service: "1")
      assert_redirected_to auth_code_path

      identity = GlobalIdentity.find_by(email_address: "newuser@example.com")
      assert identity.present?
    end
  end
end
