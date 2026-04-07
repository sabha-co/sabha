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

  # Joinable rooms filter

  test "lists joinable open rooms the bot is not in" do
    get rooms_bot_rooms_url(@bot.bot_key), params: { joinable: true }

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    room_ids = json.map { |r| r["id"] }
    # Bot is not in pets or hq (open rooms), but IS in watercooler (closed)
    assert_includes room_ids, rooms(:pets).id
    assert_includes room_ids, rooms(:hq).id
    assert_not_includes room_ids, rooms(:watercooler).id
  end

  test "joinable rooms excludes rooms bot is already in" do
    # Join an open room first
    rooms(:hq).accept_join!(@bot)

    get rooms_bot_rooms_url(@bot.bot_key), params: { joinable: true }

    assert_response :success
    room_ids = response.parsed_body.map { |r| r["id"] }
    assert_not_includes room_ids, rooms(:hq).id
  end

  # Room creation

  test "create an open room" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "Bot Room", type: "open" },
      as: :json

    assert_response :created
    json = response.parsed_body
    assert_equal "Bot Room", json["name"]
    assert_equal "Open", json["type"]
  end

  test "create a closed room" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "Secret Bot Room", type: "closed" },
      as: :json

    assert_response :created
    json = response.parsed_body
    assert_equal "Secret Bot Room", json["name"]
    assert_equal "Closed", json["type"]
  end

  test "create room requires a name" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { type: "open" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "create room requires a valid type" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "Bad Type", type: "direct" },
      as: :json

    assert_response :unprocessable_entity
  end

  test "bot is auto-joined to created room" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "My Room", type: "open" },
      as: :json

    room = Room.find(response.parsed_body["id"])
    assert room.users.include?(@bot)
  end

  test "bot is recorded as creator of room" do
    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "My Room", type: "open" },
      as: :json

    room = Room.find(response.parsed_body["id"])
    assert_equal @bot.id, room.creator_id
  end

  # Room update

  test "creator bot can rename room" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch room_bot_update_room_url(room, @bot.bot_key),
      params: { name: "New Name" },
      as: :json

    assert_response :success
    assert_equal "New Name", response.parsed_body["name"]
    assert_equal "New Name", room.reload.name
  end

  test "non-creator bot cannot update room" do
    room = rooms(:watercooler) # created by david, not bender

    patch room_bot_update_room_url(room, @bot.bot_key),
      params: { name: "Nope" },
      as: :json

    assert_response :forbidden
  end

  test "update requires a name" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch room_bot_update_room_url(room, @bot.bot_key),
      params: {},
      as: :json

    assert_response :unprocessable_entity
  end

  # Room archive

  test "creator bot can archive room" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Doomed" }, users: @bot)
    Current.reset

    delete room_bot_archive_room_url(room, @bot.bot_key)

    assert_response :no_content
    assert_not room.reload.active?
  end

  test "non-creator bot cannot archive room" do
    room = rooms(:watercooler)

    delete room_bot_archive_room_url(room, @bot.bot_key)

    assert_response :forbidden
  end

  # Auth

  test "session-authenticated user cannot use room management" do
    sign_in users(:david)

    post rooms_bot_create_room_url(@bot.bot_key),
      params: { name: "Sneaky", type: "open" },
      as: :json

    assert_response :forbidden
  end
end
