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

  # Single message read

  test "returns a single message by id" do
    message = messages(:bender_message)

    get room_bot_message_read_url(@room, @bot.bot_key, message)

    assert_response :success
    json = response.parsed_body
    assert_equal message.id, json["id"]
    assert json["creator"].is_a?(Hash)
    assert json["body"].is_a?(Hash)
    assert json["created_at"].present?
  end

  test "returns 404 for message in room bot is not in" do
    other_room = rooms(:designers)
    # Create a message in the other room to look up
    message = other_room.messages.create!(
      creator: users(:david),
      body: "test",
      client_message_id: Random.uuid
    )

    get room_bot_message_read_url(other_room, @bot.bot_key, message)

    assert_response :not_found
  end

  test "returns 404 for nonexistent message" do
    get room_bot_message_read_url(@room, @bot.bot_key, 999999)

    assert_response :not_found
  end
end
