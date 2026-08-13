require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include TurnstileTestHelper

  setup do
    @join_code = Current.account.join_code.code
    @original_auth_method = ENV["AUTH_METHOD"]
  end

  teardown do
    if @original_auth_method.nil?
      ENV.delete("AUTH_METHOD")
    else
      ENV["AUTH_METHOD"] = @original_auth_method
    end
  end

  test "show" do
    sign_in :david
    get user_url(users(:david))
    assert_response :ok
  end

  test "show renders the profile inside the app shell" do
    sign_in :david
    get user_url(users(:jason))

    assert_response :ok
    assert_select ".navbar-title", text: "Profile"
    assert_select ".profile-hero__name", text: users(:jason).name
    assert_select ".profile-stat__label", text: "Shared rooms"
    assert_select ".profile-card__title", text: "Moderation"
  end

  test "show labels the third stat Rooms on your own profile and hides moderation" do
    sign_in :david
    get user_url(users(:david))

    assert_select ".profile-stat__label", text: "Rooms"
    assert_select ".profile-card__title", text: "Moderation", count: 0
  end

  test "show as a non-staff member offers actions without moderation" do
    sign_in :kevin
    get user_url(users(:david))

    assert_select ".profile-hero__actions .btn", text: "Message"
    assert_select ".profile-hero__actions .btn", text: "Block"
    assert_select ".profile-card__title", text: "Moderation", count: 0
  end

  test "new redirects to sso when SSO auth enabled" do
    ENV["AUTH_METHOD"] = "sso"

    get join_url(@join_code)

    assert_redirected_to sso_handshake_url(return_to: "/join/#{@join_code}")
    assert_equal @join_code, session[:pending_join_code]
  end

  test "new rejects invalid join code before redirecting to sso" do
    ENV["AUTH_METHOD"] = "sso"

    get join_url("INVALID_CODE_123")

    assert_redirected_to root_url
    assert_match /not valid/, flash[:alert]
    assert_nil session[:pending_join_code]
  end

  test "new rejects expired join code before redirecting to sso" do
    ENV["AUTH_METHOD"] = "sso"
    Current.account.join_code.update!(expires_at: 1.day.ago)

    get join_url(@join_code)

    assert_redirected_to root_url
    assert_match /expired/, flash[:alert]
    assert_nil session[:pending_join_code]
  end

  test "create redirects to sso when SSO auth enabled" do
    ENV["AUTH_METHOD"] = "sso"

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "secure_password_123"
        }
      )
    end

    assert_redirected_to sso_handshake_url(return_to: "/join/#{@join_code}")
  end

  test "create with password auth requires email verification" do
    ENV["AUTH_METHOD"] = "password"

    assert_emails 1 do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "secure_password_123"
        }
      )
    end

    assert_redirected_to new_session_url(email_address: "newuser@example.com")
    assert_match /check your email to verify/, flash[:notice]

    user = User.find_by(email_address: "newuser@example.com")
    assert_not user.verified?
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "create with OTP auth requires email verification" do
    ENV["AUTH_METHOD"] = "otp"

    assert_emails 1 do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "New User",
          email_address: "newuser@example.com"
        }
      )
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
    post join_url(@join_code), params: with_turnstile_response(
      user: {
        name: "New OTP User",
        email_address: "otpuser@example.com"
      }
    )

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
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Hacker",
          email_address: "hacker@example.com",
          password: ""
        }
      )
    end

    assert_response :unprocessable_entity
    assert_match /Password can't be blank/, flash[:alert]
  end

  test "create with short password is rejected" do
    ENV["AUTH_METHOD"] = "password"

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Hacker",
          email_address: "hacker@example.com",
          password: "short"
        }
      )
    end

    assert_response :unprocessable_entity
    assert_match /Password is too short/, flash[:alert]
  end

  test "create with valid password redirects to sign-in for email verification" do
    ENV["AUTH_METHOD"] = "password"

    assert_difference -> { User.count }, 1 do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Valid User",
          email_address: "valid@example.com",
          password: "valid_password_123"
        }
      )
    end

    assert_redirected_to new_session_url(email_address: "valid@example.com")
    user = User.find_by(email_address: "valid@example.com")
    assert user.present?
    assert user.authenticate("valid_password_123")
    assert_not user.verified?
  end

  test "create increments join code usage count" do
    ENV["AUTH_METHOD"] = "password"
    join_code = Current.account.join_code

    assert_difference -> { join_code.reload.usage_count }, 1 do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "New User",
          email_address: "newuser123@example.com",
          password: "valid_password_123"
        }
      )
    end
  end

  test "create with invalid email returns 422" do
    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Hacker",
          email_address: "not-an-email",
          password: "secure_password_123"
        }
      )
    end

    assert_response :unprocessable_entity
  end

  test "create with blank email returns 422" do
    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Hacker",
          email_address: "",
          password: "secure_password_123"
        }
      )
    end

    assert_response :unprocessable_entity
  end

  test "create with nil email returns 422" do
    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Hacker",
          password: "secure_password_123"
        }
      )
    end

    assert_response :unprocessable_entity
  end

  # ============================================================================
  # Signed-in user access
  # ============================================================================

  test "join page redirects signed-in users to root" do
    sign_in :david

    get join_url(@join_code)

    assert_redirected_to root_url
  end

  test "join form submission redirects signed-in users to root" do
    sign_in :david
    ENV["AUTH_METHOD"] = "password"

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "David Again",
          email_address: "david-again@example.com",
          password: "secure_password_123"
        }
      )
    end

    assert_redirected_to root_url
  end

  # ============================================================================
  # Invalid/expired join codes
  # ============================================================================

  test "join page with invalid code redirects with alert" do
    get join_url("INVALID_CODE_123")

    assert_redirected_to root_url
    assert_match /not valid/, flash[:alert]
  end

  test "join page with expired code redirects with alert" do
    Current.account.join_code.update!(expires_at: 1.day.ago)

    get join_url(@join_code)

    assert_redirected_to root_url
    assert_match /expired/, flash[:alert]
  end

  test "join form with exhausted code redirects with alert" do
    ENV["AUTH_METHOD"] = "password"
    join_code_record = Current.account.join_code
    join_code_record.update!(usage_limit: 1, usage_count: 1)

    post join_url(@join_code), params: with_turnstile_response(
      user: {
        name: "New User",
        email_address: "newuser@example.com",
        password: "valid_password_123"
      }
    )

    assert_redirected_to root_url
    assert_match /expired/, flash[:alert]
  end

  # ============================================================================
  # Duplicate email handling
  # ============================================================================

  test "create with existing email redirects to sign-in" do
    ENV["AUTH_METHOD"] = "password"
    existing_user = users(:david)

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Impersonator",
          email_address: existing_user.email_address,
          password: "secure_password_123"
        }
      )
    end

    assert_redirected_to new_session_url(email_address: existing_user.email_address)
    assert_match /already exists/i, flash[:notice]
  end

  test "create with existing email in OTP mode starts OTP flow" do
    ENV["AUTH_METHOD"] = "otp"
    existing_user = users(:david)
    existing_user.update!(last_authenticated_at: 1.day.ago) # Mark as having authenticated before

    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: with_turnstile_response(
        user: {
          name: "Impersonator",
          email_address: existing_user.email_address
        }
      )
    end

    # Should redirect to OTP validation for existing user
    assert_redirected_to new_auth_tokens_validations_url
  end
end
