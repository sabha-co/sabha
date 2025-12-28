require "test_helper"

class AuthTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
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

  test "create with valid email sends OTP" do
    user = users(:david)

    assert_emails 1 do
      post auth_tokens_url, params: { email_address: user.email_address }
    end

    assert_redirected_to new_auth_tokens_validations_url
  end

  test "create with unknown email redirects with error" do
    post auth_tokens_url, params: { email_address: "unknown@example.com" }

    assert_redirected_to new_session_url
    assert_match /couldn't find an account/, flash[:alert]
  end

  test "create with invalid email returns 422" do
    post auth_tokens_url, params: { email_address: "not-an-email" }
    assert_response :unprocessable_entity
  end

  test "create with blank email returns 422" do
    post auth_tokens_url, params: { email_address: "" }
    assert_response :unprocessable_entity
  end

  test "create with nil email returns 422" do
    post auth_tokens_url, params: {}
    assert_response :unprocessable_entity
  end

  test "OTP request blocked when password auth enabled" do
    ENV["AUTH_METHOD"] = "password"

    post auth_tokens_url, params: { email_address: users(:david).email_address }

    assert_redirected_to new_session_url
    assert_match /not enabled/, flash[:alert]
  end

  test "rate limits OTP requests" do
    11.times do
      post auth_tokens_url, params: { email_address: users(:david).email_address }
    end

    assert_response :too_many_requests
  end

  test "rate limit resets after window expires" do
    10.times do
      post auth_tokens_url, params: { email_address: users(:david).email_address }
    end
    assert_redirected_to new_auth_tokens_validations_url

    travel 2.minutes

    post auth_tokens_url, params: { email_address: users(:david).email_address }
    assert_redirected_to new_auth_tokens_validations_url
  end
end
