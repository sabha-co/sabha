require "test_helper"

class Bots::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "search returns matching messages" do
    get api_bots_search_url(q: "post"), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    if json.any?
      msg = json.first
      assert msg["id"].present?
      assert msg["creator"].is_a?(Hash)
      assert msg["body"].is_a?(Hash)
      assert msg["room"].is_a?(Hash)
      assert msg["created_at"].present?
    end
  end

  test "search requires q param" do
    get api_bots_search_url(), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "search with blank q returns error" do
    get api_bots_search_url(q: ""), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_search_url(q: "test"), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end
end
