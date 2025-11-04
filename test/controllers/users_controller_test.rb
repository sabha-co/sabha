require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @join_code = Current.account.join_code
  end

  test "show" do
    sign_in :david
    get user_url(users(:david))
    assert_response :ok
  end

  test "create with password auth requires email verification" do
    ENV["AUTH_METHOD"] = "password"

    assert_emails 1 do
      post join_url(@join_code), params: {
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "secure_password_123"
        }
      }
    end

    assert_redirected_to root_url
    assert_match /check your email to verify/, flash[:notice]

    user = User.find_by(email_address: "newuser@example.com")
    assert_not user.verified?
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "create with OTP auth requires email verification" do
    ENV["AUTH_METHOD"] = "otp"

    assert_emails 1 do
      post join_url(@join_code), params: {
        user: {
          name: "New User",
          email_address: "newuser@example.com"
        }
      }
    end

    assert_redirected_to new_auth_tokens_validations_url
    assert_match /check your email for a verification code/, flash[:notice]

    user = User.find_by(email_address: "newuser@example.com")
    assert_not user.verified?
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "OTP validation verifies email for new users" do
    ENV["AUTH_METHOD"] = "otp"

    # Sign up new user
    post join_url(@join_code), params: {
      user: {
        name: "New OTP User",
        email_address: "otpuser@example.com"
      }
    }

    user = User.find_by(email_address: "otpuser@example.com")
    assert_not user.verified?
    assert_redirected_to new_auth_tokens_validations_url

    # Get the OTP token and validate it
    auth_token = user.auth_tokens.last
    post auth_tokens_validations_url, params: { code: auth_token.code }

    # User should now be verified and signed in
    assert user.reload.verified?
    assert parsed_cookies.signed[:session_token].present?
    assert_redirected_to root_url
  end

  test "create with blank password is rejected" do
    ENV["AUTH_METHOD"] = "password"

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: {
        user: {
          name: "Hacker",
          email_address: "hacker@example.com",
          password: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match /Password can't be blank/, flash[:alert]
  end

  test "create with short password is rejected" do
    ENV["AUTH_METHOD"] = "password"

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: {
        user: {
          name: "Hacker",
          email_address: "hacker@example.com",
          password: "short"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match /Password is too short/, flash[:alert]
  end

  test "create with valid password succeeds" do
    ENV["AUTH_METHOD"] = "password"

    assert_difference -> { User.count }, 1 do
      post join_url(@join_code), params: {
        user: {
          name: "Valid User",
          email_address: "valid@example.com",
          password: "valid_password_123"
        }
      }
    end

    assert_redirected_to root_url
    user = User.find_by(email_address: "valid@example.com")
    assert user.present?
    assert user.authenticate("valid_password_123")
  end
end
