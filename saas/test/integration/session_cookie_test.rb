# frozen_string_literal: true

require_relative "../test_helper"

class SessionCookieTest < ActionDispatch::IntegrationTest
  test "the session cookie has its own name and stays on this host" do
    get new_session_path

    session_cookie = set_cookies.find { it.start_with?("_sabha_saas_session=") }
    assert session_cookie
    assert_no_match(/domain=/i, session_cookie)
  end

  private
    def set_cookies
      Array(response.headers["set-cookie"]).flat_map { it.split("\n") }
    end
end
