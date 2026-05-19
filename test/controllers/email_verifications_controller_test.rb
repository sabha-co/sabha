require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  test "show verifies email with valid token" do
    user = users(:david)
    user.update!(verified_at: nil)
    token = user.generate_token_for(:email_verification)

    get verify_email_url(token)

    assert_redirected_to root_url
    assert user.reload.verified?
    assert_match /verified successfully/, flash[:notice]
  end

  test "show verifies email and redirects to sso when SSO auth enabled" do
    original = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "sso"
    user = users(:david)
    user.update!(verified_at: nil)
    token = user.generate_token_for(:email_verification)

    assert_no_difference -> { Session.count } do
      get verify_email_url(token)
    end

    assert_redirected_to sso_handshake_url
    assert user.reload.verified?
    assert_nil parsed_cookies.signed[:session_token]
  ensure
    original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
  end

  test "show rejects invalid token" do
    get verify_email_url("invalid_token")

    assert_redirected_to root_url
    assert_match /Invalid or expired/, flash[:alert]
  end

  test "show handles already verified user" do
    user = users(:david)
    token = user.generate_token_for(:email_verification)

    get verify_email_url(token)

    assert_redirected_to root_url
    assert_match /already verified/, flash[:notice]
  end

  test "resend sends verification email for unverified user" do
    user = users(:david)
    user.update!(verified_at: nil)

    assert_emails 1 do
      post resend_verification_url, params: { email_address: user.email_address }
    end

    assert_redirected_to new_session_url
    assert_match /Verification email sent/, flash[:notice]
  end

  test "resend handles already verified user" do
    user = users(:david)

    post resend_verification_url, params: { email_address: user.email_address }

    assert_redirected_to new_session_url
    assert_match /already verified/, flash[:notice]
  end

  test "resend handles unknown email" do
    post resend_verification_url, params: { email_address: "unknown@example.com" }

    assert_redirected_to new_session_url
    assert_match /Unable to resend/, flash[:alert]
  end

  test "rate limits resend requests" do
    user = users(:david)
    user.update!(verified_at: nil)

    4.times do
      post resend_verification_url, params: { email_address: user.email_address }
    end

    assert_redirected_to root_url
    assert_match /Too many requests/, flash[:alert]
  end

  test "rate limit resets after window expires" do
    user = users(:david)
    user.update!(verified_at: nil)

    3.times do
      post resend_verification_url, params: { email_address: user.email_address }
    end
    assert_redirected_to new_session_url

    travel 2.minutes

    post resend_verification_url, params: { email_address: user.email_address }
    assert_redirected_to new_session_url
    refute_match /Too many/, flash[:alert].to_s
  end

  # Email change confirmation tests

  test "confirm_email_change updates email with valid token" do
    user = users(:david)
    user.update!(unconfirmed_email: "newemail@example.com")
    token = user.generate_token_for(:email_change)

    assert_emails 1 do
      get confirm_email_change_url(token)
    end

    assert_redirected_to root_url
    assert_match /successfully updated/, flash[:notice]
    user.reload
    assert_equal "newemail@example.com", user.email_address
    assert_nil user.unconfirmed_email
  end

  test "confirm_email_change rejects invalid token" do
    get confirm_email_change_url("invalid_token")

    assert_redirected_to root_url
    assert_match /Invalid or expired/, flash[:alert]
  end

  test "confirm_email_change handles already confirmed email change" do
    user = users(:david)
    # Generate token first, then clear unconfirmed_email
    token = user.generate_token_for(:email_change)
    user.update!(unconfirmed_email: nil)

    get confirm_email_change_url(token)

    assert_redirected_to root_url
    assert_match /already confirmed or cancelled/, flash[:notice]
  end
end
