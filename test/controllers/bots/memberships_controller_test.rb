require "test_helper"

class Bots::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  # Join room

  test "bot can join an open room" do
    room = rooms(:hq) # open room, bot is not a member

    post room_bot_join_room_url(room, @bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal room.id, json["id"]
    assert room.reload.users.include?(@bot)
  end

  test "bot cannot join a closed room" do
    room = rooms(:designers) # closed room

    post room_bot_join_room_url(room, @bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 for nonexistent room" do
    post room_bot_join_room_url(999999, @bot.bot_key)

    assert_response :not_found
  end

  # Leave room

  test "bot can leave a room" do
    room = rooms(:watercooler) # bot is a member

    delete room_bot_leave_room_url(room, @bot.bot_key)

    assert_response :no_content
  end

  test "bot cannot leave a direct message room" do
    Current.user = @bot
    dm = Rooms::Direct.find_or_create_for([ @bot, users(:david) ])
    Current.reset

    delete room_bot_leave_room_url(dm, @bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 when leaving room bot is not in" do
    delete room_bot_leave_room_url(rooms(:designers), @bot.bot_key)

    assert_response :not_found
  end

  # Auth

  test "invalid bot key redirects to sign in" do
    post room_bot_join_room_url(rooms(:hq), "999-invalid")

    assert_redirected_to new_session_url
  end

  test "session-authenticated user cannot use bot join" do
    sign_in users(:david)

    post room_bot_join_room_url(rooms(:hq), @bot.bot_key)

    assert_response :forbidden
  end
end
