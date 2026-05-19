require "test_helper"

class AuthTokens::ValidationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:david)
    @original_auth_method = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "otp"
  end

  teardown do
    if @original_auth_method.nil?
      ENV.delete("AUTH_METHOD")
    else
      ENV["AUTH_METHOD"] = @original_auth_method
    end
  end

  test "valid OTP code signs in user" do
    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: auth_token.code }

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token].present?
    assert auth_token.reload.used_at.present?
  end

  test "invalid OTP code rejects login" do
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: "000000" }

    assert_redirected_to new_auth_tokens_validations_path
    assert_match /Invalid or expired/, flash[:alert]
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "expired OTP code rejects login" do
    auth_token = @user.auth_tokens.create!(expires_at: 1.minute.ago)
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: auth_token.code }

    assert_redirected_to new_auth_tokens_validations_path
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "used OTP code rejects login" do
    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now, used_at: Time.current)
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: auth_token.code }

    assert_redirected_to new_auth_tokens_validations_path
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "token-based login (magic link) signs in user" do
    auth_token = @user.auth_tokens.create!(expires_at: 24.hours.from_now)

    get sign_in_with_token_url(token: auth_token.token)

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token].present?
  end

  test "code-based OTP validation redirects to sso when SSO auth enabled" do
    ENV["AUTH_METHOD"] = "sso"

    post auth_tokens_validations_url, params: { code: "000000" }

    assert_redirected_to sso_handshake_url
  end

  test "token-based magic link redirects to sso when SSO auth enabled" do
    ENV["AUTH_METHOD"] = "sso"
    auth_token = @user.auth_tokens.create!(expires_at: 24.hours.from_now)

    get sign_in_with_token_url(token: auth_token.token)

    assert_redirected_to sso_handshake_url
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "OTP validation verifies unverified user email" do
    @user.update!(verified_at: nil)
    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: auth_token.code }

    assert @user.reload.verified?
  end

  test "rate limits OTP validation attempts" do
    post auth_tokens_url, params: { email_address: @user.email_address }

    11.times do
      post auth_tokens_validations_url, params: { code: "000000" }
    end

    assert_response :too_many_requests
  end

  test "rate limit resets after window expires" do
    post auth_tokens_url, params: { email_address: @user.email_address }

    10.times do
      post auth_tokens_validations_url, params: { code: "000000" }
    end
    assert_redirected_to new_auth_tokens_validations_path

    travel 2.minutes

    post auth_tokens_validations_url, params: { code: "000000" }
    assert_redirected_to new_auth_tokens_validations_path
  end

  test "deactivated user cannot authenticate via magic link" do
    auth_token = @user.auth_tokens.create!(expires_at: 24.hours.from_now)
    token_value = auth_token.token

    # Deactivate user (this deletes auth_tokens, but we'll verify auth would fail anyway)
    @user.deactivate

    # Recreate a token directly in DB to simulate edge case
    auth_token = AuthToken.create!(user: @user, expires_at: 24.hours.from_now)

    get sign_in_with_token_url(token: auth_token.token)

    # Should redirect but NOT create session (authenticated_as returns early for deactivated)
    assert_nil parsed_cookies.signed[:session_token], "Deactivated user should not be authenticated"
  end
end
