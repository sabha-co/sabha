require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  test "new displays password reset form" do
    get new_password_reset_url

    assert_response :success
    assert_select "legend", "Reset Your Password"
  end

  test "create sends password reset email for existing user" do
    user = users(:david)

    assert_emails 1 do
      post password_resets_url, params: { email_address: user.email_address }
    end

    assert_redirected_to new_session_url
    assert_match /Password reset instructions sent/, flash[:notice]
  end

  test "create does not reveal if email does not exist" do
    post password_resets_url, params: { email_address: "nonexistent@example.com" }

    assert_redirected_to new_session_url
    assert_match /If that email address is in our system/, flash[:notice]
  end

  test "edit displays password reset form with valid token" do
    user = users(:david)
    token = user.generate_token_for(:password_reset)

    get edit_password_reset_url(token)

    assert_response :success
    assert_select "legend", "Set New Password"
  end

  test "edit redirects with invalid token" do
    get edit_password_reset_url("invalid_token")

    assert_redirected_to new_session_url
    assert_match /Invalid or expired/, flash[:alert]
  end

  test "update resets password with valid token and matching passwords" do
    user = users(:david)
    token = user.generate_token_for(:password_reset)
    new_password = "new_secure_password_123"

    patch password_reset_url(token), params: {
      password: new_password,
      password_confirmation: new_password
    }

    assert_redirected_to root_url
    assert_match /reset successfully/, flash[:notice]
    assert parsed_cookies.signed[:session_token].present?
    assert user.reload.authenticate(new_password)
  end

  test "update verifies email for unverified user when resetting password" do
    user = users(:david)
    user.update!(verified_at: nil)
    token = user.generate_token_for(:password_reset)
    new_password = "new_secure_password_123"

    assert_not user.verified?

    patch password_reset_url(token), params: {
      password: new_password,
      password_confirmation: new_password
    }

    assert user.reload.verified?
    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token].present?
  end

  test "update does not change verified_at for already verified user" do
    user = users(:david)
    original_verified_at = user.verified_at
    token = user.generate_token_for(:password_reset)
    new_password = "new_secure_password_123"

    patch password_reset_url(token), params: {
      password: new_password,
      password_confirmation: new_password
    }

    assert_equal original_verified_at.to_i, user.reload.verified_at.to_i
  end

  test "update fails with mismatched passwords" do
    user = users(:david)
    token = user.generate_token_for(:password_reset)

    patch password_reset_url(token), params: {
      password: "new_secure_password_123",
      password_confirmation: "different_password_123"
    }

    assert_response :unprocessable_entity
    assert_match /confirmation/, response.body.downcase
  end

  test "update fails with invalid token" do
    patch password_reset_url("invalid_token"), params: {
      password: "new_secure_password_123",
      password_confirmation: "new_secure_password_123"
    }

    assert_redirected_to new_session_url
    assert_match /Invalid or expired/, flash[:alert]
  end

  test "update fails with short password" do
    user = users(:david)
    token = user.generate_token_for(:password_reset)

    patch password_reset_url(token), params: {
      password: "short",
      password_confirmation: "short"
    }

    assert_response :unprocessable_entity
    assert_match /too short/, response.body.downcase
  end
end
