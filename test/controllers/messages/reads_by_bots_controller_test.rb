require "test_helper"

class Messages::ReadsByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "returns messages from a room the bot is a member of" do
    get room_bot_messages_read_url(@room, @bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)
  end

  test "each message includes expected fields" do
    get room_bot_messages_read_url(@room, @bot.bot_key)

    assert_response :success
    json = response.parsed_body
    return if json.empty?

    msg = json.first
    assert msg["id"].present?
    assert msg["creator"].is_a?(Hash)
    assert msg["creator"]["id"].present?
    assert msg["creator"]["name"].present?
    assert msg["body"].is_a?(Hash)
    assert msg.key?("mentionees")
    assert msg["created_at"].present?
    assert_equal false, msg["has_attachment"]
    assert_nil msg["attachment"]
  end

  test "returns 404 for room the bot is not a member of" do
    get room_bot_messages_read_url(rooms(:designers), @bot.bot_key)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get room_bot_messages_read_url(@room, "999-invalidtoken")

    assert_redirected_to new_session_url
  end
end
