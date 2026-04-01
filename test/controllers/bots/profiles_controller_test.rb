require "test_helper"

class Bots::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "updates bot name" do
    patch bot_profile_url(@bot.bot_key),
      params: { name: "Renamed Bot" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert_equal "Renamed Bot", json["name"]
    assert_equal "Renamed Bot", @bot.reload.name
  end

  test "updates webhook_url" do
    patch bot_profile_url(@bot.bot_key),
      params: { webhook_url: "http://example.com/new-hook" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert_equal "http://example.com/new-hook", json["webhook_url"]
    assert_equal "http://example.com/new-hook", @bot.reload.webhook_url
  end

  test "updates via legacy mentions_url param" do
    patch bot_profile_url(@bot.bot_key),
      params: { mentions_url: "http://example.com/legacy" },
      as: :json

    assert_response :success
    assert_equal "http://example.com/legacy", @bot.reload.webhook_url
  end

  test "response includes name and webhook_url" do
    patch bot_profile_url(@bot.bot_key),
      params: { name: "Check" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert json.key?("name")
    assert json.key?("webhook_url")
  end

  test "invalid bot key redirects to sign in" do
    patch bot_profile_url("999-invalidtoken"),
      params: { name: "Nope" },
      as: :json

    assert_redirected_to new_session_url
  end

  test "partial update preserves existing webhook" do
    original_webhook_url = @bot.webhook_url
    assert original_webhook_url.present?

    patch bot_profile_url(@bot.bot_key),
      params: { name: "Partial" },
      as: :json

    assert_response :success
    assert_equal "Partial", @bot.reload.name
    assert_equal original_webhook_url, @bot.webhook_url
  end

  test "session-authenticated human cannot update bot profile" do
    user = users(:david)
    post session_url, params: { email_address: user.email_address, password: "secret123456" }

    patch bot_profile_url(@bot.bot_key),
      params: { name: "Hijacked" },
      as: :json

    assert_response :forbidden
    assert_not_equal "Hijacked", @bot.reload.name
  end
end
