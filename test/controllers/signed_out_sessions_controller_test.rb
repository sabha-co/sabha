require "test_helper"

class SignedOutSessionsControllerTest < ActionDispatch::IntegrationTest
  test "show renders without triggering SSO re-auth when unauthenticated" do
    original = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "sso"

    get signed_out_session_url

    assert_response :success
  ensure
    original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
  end

  test "show redirects authenticated users to root" do
    sign_in :david

    get signed_out_session_url

    assert_redirected_to root_url
  end
end
