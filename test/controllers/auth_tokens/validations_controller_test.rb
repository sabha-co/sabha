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

  test "OTP validation verifies unverified user email" do
    @user.update!(verified_at: nil)
    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    post auth_tokens_url, params: { email_address: @user.email_address }

    post auth_tokens_validations_url, params: { code: auth_token.code }

    assert @user.reload.verified?
  end
end
