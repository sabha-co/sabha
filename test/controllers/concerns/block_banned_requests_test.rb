require "test_helper"

class BlockBannedRequestsTest < ActionDispatch::IntegrationTest
  include TurnstileTestHelper

  setup do
    @original_auth_method = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "password"
    Ban.create!(user: users(:kevin), ip_address: "203.0.113.1")
    @join_code = Current.account.join_code.code
  end

  teardown do
    if @original_auth_method.nil?
      ENV.delete("AUTH_METHOD")
    else
      ENV["AUTH_METHOD"] = @original_auth_method
    end
  end

  test "sign-in from banned IP is blocked with 429" do
    post session_url,
      params: { email_address: "david@example.com", password: "secret123456" },
      headers: { "REMOTE_ADDR" => "203.0.113.1" }

    assert_response :too_many_requests
  end

  test "registration from banned IP is blocked with 429" do
    post join_url(@join_code),
      params: with_turnstile_response(
        user: { name: "Banned", email_address: "banned@example.com", password: "secret123456" }
      ),
      headers: { "REMOTE_ADDR" => "203.0.113.1" }

    assert_response :too_many_requests
  end

  test "OTP request from banned IP is blocked with 429" do
    ENV["AUTH_METHOD"] = "otp"

    post auth_tokens_url,
      params: { email_address: "david@example.com" },
      headers: { "REMOTE_ADDR" => "203.0.113.1" }

    assert_response :too_many_requests
  end

  test "sign-in from non-banned IP is allowed" do
    post session_url,
      params: { email_address: "david@example.com", password: "secret123456" },
      headers: { "REMOTE_ADDR" => "203.0.113.99" }

    assert_response :redirect
  end

  test "authenticated POST from banned IP is not blocked" do
    sign_in :david
    room = rooms(:watercooler)

    post room_messages_url(room, format: :turbo_stream),
      params: { message: { body: "Test", client_message_id: "test-123" } },
      headers: { "REMOTE_ADDR" => "203.0.113.1" }

    assert_response :success
  end
end
