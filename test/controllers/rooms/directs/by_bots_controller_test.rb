require "test_helper"

class Rooms::Directs::ByBotsControllerTest < ActionDispatch::IntegrationTest
  test "bot can create DM with user" do
    bot = users(:bender)

    # bot_key is a path parameter, not a query param
    post api_bots_direct_messages_url, params: { user_ids: [ users(:jz).id ] }, headers: bot_headers(bot.bot_key)

    assert_response :created
    json = JSON.parse(response.body)
    assert json["room"]["id"].present?

    room = Room.find(json["room"]["id"])
    assert room.direct?
    assert room.users.include?(bot)
    assert room.users.include?(users(:jz))
  end

  test "bot creating existing DM returns ok status" do
    bot = users(:bender)

    # Create the room first
    post api_bots_direct_messages_url, params: { user_ids: [ users(:jz).id ] }, headers: bot_headers(bot.bot_key)
    assert_response :created
    first_room_id = JSON.parse(response.body)["room"]["id"]

    # Creating again returns existing room with :ok status
    post api_bots_direct_messages_url, params: { user_ids: [ users(:jz).id ] }, headers: bot_headers(bot.bot_key)
    assert_response :ok
    second_room_id = JSON.parse(response.body)["room"]["id"]

    assert_equal first_room_id, second_room_id
  end

  test "bot can create group DM" do
    bot = users(:bender)

    post api_bots_direct_messages_url, params: { user_ids: [ users(:jz).id, users(:kevin).id ] }, headers: bot_headers(bot.bot_key)

    assert_response :created
    json = JSON.parse(response.body)
    room = Room.find(json["room"]["id"])

    assert room.direct?
    assert_equal 3, room.users.count
    assert room.users.include?(bot)
    assert room.users.include?(users(:jz))
    assert room.users.include?(users(:kevin))
  end

  test "invalid bot token redirects to sign in" do
    post api_bots_direct_messages_url, params: { user_ids: [ users(:david).id ] }, headers: bot_headers("invalid_token")

    assert_redirected_to new_session_url
  end

  test "creating DM with non-existent user creates bot-only room" do
    bot = users(:bender)

    # Non-existent user ID is filtered out, bot creates DM with just itself
    post api_bots_direct_messages_url, params: { user_ids: [ 999999 ] }, headers: bot_headers(bot.bot_key)

    assert_response :created
    json = JSON.parse(response.body)
    room = Room.find(json["room"]["id"])

    # Room contains only the bot (note to self)
    assert_equal 1, room.users.count
    assert room.users.include?(bot)
  end
end
