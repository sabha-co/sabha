require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_session_url
    assert_response :success
  end

  test "new redirects to first run when no users exist" do
    # Delete dependent records first to avoid foreign key violations from library_watch_histories
    ActiveRecord::Base.connection.disable_referential_integrity do
      User.destroy_all
    end

    get new_session_url

    assert_redirected_to first_run_url
  end

  test "new denied with incompatible browser" do
    get new_session_url
    assert_response :success
  end

  test "new allowed with compatible browser" do
    get new_session_url
    assert_response :success
  end

  test "create with valid credentials" do
    assert_difference -> { Session.count }, +1 do
      post session_url, params: { email_address: "david@37signals.com", password: "secret123456" }
    end

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token]
  end

  test "create with invalid credentials redirects to new session" do
    post session_url, params: { email_address: "david@37signals.com", password: "wrong" }

    assert_redirected_to new_session_url(email_address: "david@37signals.com")
    assert_nil parsed_cookies.signed[:session_token]
    assert_equal "Invalid email or password.", flash[:alert]
  end

  test "create with unverified email redirects with verification message" do
    user = users(:david)
    user.update!(verified_at: nil)

    post session_url, params: { email_address: user.email_address, password: "secret123456" }

    assert_redirected_to new_session_url(email_address: user.email_address)
    assert_nil parsed_cookies.signed[:session_token]
    assert_match /verify your email/, flash[:alert]
  end

  test "destroy" do
    sign_in :david
    session = users(:david).sessions.last

    assert_difference -> { Session.count }, -1 do
      delete session_url
    end

    assert_redirected_to root_url
    assert_not cookies[:session_token].present?
    assert_not Session.exists?(session.id)
  end

  test "destroy removes the push subscription for the device" do
    sign_in :david

    assert_difference -> { users(:david).push_subscriptions.count }, -1 do
      delete session_url, params: { push_subscription_endpoint: push_subscriptions(:david_chrome).endpoint }
    end

    assert_redirected_to root_url
    assert_not cookies[:session_token].present?
  end

  test "create with invalid email returns 422" do
    post session_url, params: { email_address: "not-an-email", password: "secret123456" }
    assert_response :unprocessable_entity
  end

  test "create with blank email returns 422" do
    post session_url, params: { email_address: "", password: "secret123456" }
    assert_response :unprocessable_entity
  end

  test "create with nil email returns 422" do
    post session_url, params: { password: "secret123456" }
    assert_response :unprocessable_entity
  end

  test "password login blocked when OTP auth enabled" do
    original = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "otp"

    post session_url, params: { email_address: "david@37signals.com", password: "secret123456" }

    assert_redirected_to new_session_url
    assert_match /not enabled/, flash[:alert]
  ensure
    original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
  end

  test "rate limits login attempts" do
    11.times do
      post session_url, params: { email_address: "david@37signals.com", password: "wrong" }
    end

    assert_redirected_to new_session_url
    assert_match /Too many sign in attempts/, flash[:alert]
  end

  test "rate limit resets after window expires" do
    10.times do
      post session_url, params: { email_address: "david@37signals.com", password: "wrong" }
    end
    refute_match /Too many/, flash[:alert].to_s

    travel 4.minutes

    post session_url, params: { email_address: "david@37signals.com", password: "wrong" }
    assert_response :redirect
    refute_match /Too many/, flash[:alert].to_s
  end
end
