# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class SettingsControllerTest < ActionDispatch::IntegrationTest
    test "show requires authentication" do
      get settings_path
      assert_redirected_to new_session_path
    end

    test "show renders form when authenticated" do
      sign_in_global_identity(global_identities(:alice))
      get settings_path
      assert_response :success
    end

    test "show displays workspaces list" do
      sign_in_global_identity(global_identities(:alice))
      get settings_path
      assert_response :success
      assert_select "legend", /Your Workspaces/i
    end

    test "update requires authentication" do
      patch settings_path, params: { global_identity: { email_address: "new@example.com" } }
      assert_redirected_to new_session_path
    end

    test "update with same email redirects with no changes" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: identity.email_address } }
      assert_redirected_to settings_path
      assert_equal "No changes made", flash[:notice]
    end

    test "update with taken email shows error" do
      identity = global_identities(:alice)
      other = global_identities(:bob)
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: other.email_address } }
      assert_response :unprocessable_entity
    end

    test "update with new email stores pending email and sends verification code" do
      identity = global_identities(:alice)
      original_email = identity.email_address
      sign_in_global_identity(identity)
      new_email = "newemail@example.com"

      assert_difference "AuthCode.count", 1 do
        assert_enqueued_emails 1 do
          patch settings_path, params: { global_identity: { email_address: new_email } }
        end
      end

      # User stays signed in and redirects to auth code entry
      assert_redirected_to auth_code_path
      assert_match /Enter the verification code/, flash[:notice]

      # Email NOT changed yet - stored as pending
      identity.reload
      assert_equal original_email, identity.email_address
      assert_equal new_email, identity.unconfirmed_email
      assert identity.verified_at.present?, "Should remain verified"

      # Auth code has email_change purpose
      auth_code = AuthCode.last
      assert auth_code.email_change?
    end

    test "update with same email cancels pending email change" do
      identity = global_identities(:alice)
      identity.update!(unconfirmed_email: "alice-pending-change@example.com")
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: identity.email_address } }
      assert_redirected_to settings_path

      identity.reload
      assert_nil identity.unconfirmed_email
    end

    test "update with blank email shows error" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      assert_no_difference "AuthCode.count" do
        patch settings_path, params: { global_identity: { email_address: "" } }
      end

      assert_response :unprocessable_entity
    end

    test "update sends verification code to the new email address" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)
      new_email = "newemail@example.com"

      patch settings_path, params: { global_identity: { email_address: new_email } }

      # Verify the email is sent to the NEW address, not the old one
      auth_code = AuthCode.last
      mail = AuthCodeMailer.code(auth_code)
      assert_equal [ new_email ], mail.to
      assert_not_equal [ identity.email_address ], mail.to
    end
  end
end
