# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    test "new renders signup form" do
      get new_registration_path
      assert_response :success
    end

    test "create with blank email redirects with error" do
      post registration_path, params: { email_address: "" }
      assert_redirected_to new_registration_path
      assert_equal "Please enter an email address", flash[:alert]
    end

    test "create with existing email sends sign_in auth code (same message as new)" do
      existing_identity = global_identities(:alice)

      assert_difference "AuthCode.count", 1 do
        assert_enqueued_emails 1 do
          post registration_path, params: { email_address: existing_identity.email_address }
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
            post registration_path, params: { email_address: new_email }
          end
        end
      end

      assert_redirected_to auth_code_path
      assert_match /Check your email for a verification code/, flash[:notice]

      # GlobalIdentity should be created
      identity = GlobalIdentity.find_by(email_address: new_email)
      assert identity.present?
      assert_nil identity.verified_at

      # Auth code should be for sign_up
      auth_code = AuthCode.last
      assert_equal identity, auth_code.global_identity
      assert auth_code.sign_up?
    end

    test "create normalizes email to lowercase" do
      post registration_path, params: { email_address: "  NewUser@Example.COM  " }
      assert_redirected_to auth_code_path

      identity = GlobalIdentity.find_by(email_address: "newuser@example.com")
      assert identity.present?
    end
  end
end
