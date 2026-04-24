require "test_helper"

class Bots::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  # Join room

  test "bot can join an open room" do
    room = rooms(:hq) # open room, bot is not a member

    post api_bots_room_membership_url(room), headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal room.id, json["id"]
    assert room.reload.users.include?(@bot)
  end

  test "bot cannot join a closed room" do
    room = rooms(:designers) # closed room

    post api_bots_room_membership_url(room), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 for nonexistent room" do
    post api_bots_room_membership_url(999999), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Leave room

  test "bot can leave a room" do
    room = rooms(:watercooler) # bot is a member

    delete api_bots_room_membership_url(room), headers: bot_headers(@bot.bot_key)

    assert_response :no_content
  end

  test "bot cannot leave a direct message room" do
    Current.user = @bot
    dm = Rooms::Direct.find_or_create_for([ @bot, users(:david) ])
    Current.reset

    delete api_bots_room_membership_url(dm), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 when leaving room bot is not in" do
    delete api_bots_room_membership_url(rooms(:designers)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Auth

  test "invalid bot key redirects to sign in" do
    post api_bots_room_membership_url(rooms(:hq)), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  test "session-authenticated user cannot use bot join" do
    sign_in users(:david)

    post api_bots_room_membership_url(rooms(:hq)), headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end
end
