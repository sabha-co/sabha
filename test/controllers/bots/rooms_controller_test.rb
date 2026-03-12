require "test_helper"

class Bots::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "lists rooms the bot is a member of" do
    get rooms_bot_rooms_url(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    room_names = json.map { |r| r["name"] }
    assert_includes room_names, rooms(:watercooler).name
  end

  test "each room includes id, name, type, and messages_url" do
    get rooms_bot_rooms_url(@bot.bot_key)

    assert_response :success
    room = response.parsed_body.first
    assert room["id"].present?
    assert room["name"].present?
    assert room["type"].present?
    assert room["messages_url"].present?
  end

  test "excludes threads from room list" do
    get rooms_bot_rooms_url(@bot.bot_key)

    assert_response :success
    types = response.parsed_body.map { |r| r["type"] }
    assert_not_includes types, "Thread"
  end

  test "invalid bot key redirects to sign in" do
    get rooms_bot_rooms_url("999-invalidtoken")

    assert_redirected_to new_session_url
  end
end
