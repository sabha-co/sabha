require "test_helper"

class AuthTokensControllerTest < ActionDispatch::IntegrationTest
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
end
