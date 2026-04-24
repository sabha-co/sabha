require "test_helper"

class API::Bots::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "updates bot name" do
    patch api_bots_profile_url,
      params: { name: "Renamed Bot" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal "Renamed Bot", json["name"]
    assert_equal "Renamed Bot", @bot.reload.name
  end

  test "updates webhook_url" do
    patch api_bots_profile_url,
      params: { webhook_url: "http://example.com/new-hook" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal "http://example.com/new-hook", json["webhook_url"]
    assert_equal "http://example.com/new-hook", @bot.reload.webhook_url
  end

  test "updates via legacy mentions_url param" do
    patch api_bots_profile_url,
      params: { mentions_url: "http://example.com/legacy" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal "http://example.com/legacy", @bot.reload.webhook_url
  end

  test "response includes name and webhook_url" do
    patch api_bots_profile_url,
      params: { name: "Check" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.key?("name")
    assert json.key?("webhook_url")
  end

  test "invalid bot key redirects to sign in" do
    patch api_bots_profile_url,
      params: { name: "Nope" },
      as: :json, headers: bot_headers("999-invalidtoken")

    assert_redirected_to new_session_url
  end

  test "partial update preserves existing webhook" do
    original_webhook_url = @bot.webhook_url
    assert original_webhook_url.present?

    patch api_bots_profile_url,
      params: { name: "Partial" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal "Partial", @bot.reload.name
    assert_equal original_webhook_url, @bot.webhook_url
  end

  test "session-authenticated human cannot update bot profile" do
    user = users(:david)
    post session_url, params: { email_address: user.email_address, password: "secret123456" }

    patch api_bots_profile_url,
      params: { name: "Hijacked" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
    assert_not_equal "Hijacked", @bot.reload.name
  end
end
