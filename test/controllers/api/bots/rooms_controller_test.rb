require "test_helper"

class API::Bots::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "lists rooms the bot is a member of" do
    get api_bots_rooms_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    room_names = json.map { |r| r["name"] }
    assert_includes room_names, rooms(:watercooler).name
  end

  test "each room includes id, name, type, and messages_url" do
    get api_bots_rooms_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    room = response.parsed_body.first
    assert room["id"].present?
    assert room["name"].present?
    assert room["type"].present?
    assert room["messages_url"].present?
  end

  test "excludes threads from room list" do
    get api_bots_rooms_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    types = response.parsed_body.map { |r| r["type"] }
    assert_not_includes types, "Thread"
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_rooms_url, headers: bot_headers("999-invalidtoken")

    assert_redirected_to new_session_url
  end

  test "valid bot key works when SSO auth enabled" do
    original = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "sso"

    get api_bots_rooms_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
  ensure
    original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
  end

  # Joinable rooms filter

  test "lists joinable open rooms the bot is not in" do
    get api_bots_rooms_url, params: { joinable: true }, headers: bot_headers(@bot.bot_key)

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

    get api_bots_rooms_url, params: { joinable: true }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    room_ids = response.parsed_body.map { |r| r["id"] }
    assert_not_includes room_ids, rooms(:hq).id
  end

  test "joinable filter only returns open rooms the bot has not joined" do
    rooms(:hq).accept_join!(@bot)

    get api_bots_rooms_url, params: { joinable: true }, headers: bot_headers(@bot.bot_key)

    room_ids = response.parsed_body.map { |r| r["id"] }
    joined_room_ids = @bot.memberships.visible.pluck(:room_id)
    assert_empty (room_ids & joined_room_ids), "joinable list must not contain rooms the bot is in"
  end

  # Query and pagination

  test "index filters by query against room name" do
    get api_bots_rooms_url, params: { query: "Talk" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    names = response.parsed_body.map { |r| r["name"] }
    assert_includes names, rooms(:watercooler).name # "All Talk"
    assert names.all? { |n| n.downcase.include?("talk") }, "expected only Talk-matching rooms, got #{names.inspect}"
  end

  test "index returns no rooms for non-matching query" do
    get api_bots_rooms_url, params: { query: "ZzzNoSuchRoom" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_empty response.parsed_body
  end

  test "blank query returns the full set" do
    get api_bots_rooms_url, headers: bot_headers(@bot.bot_key)
    unfiltered = response.parsed_body.map { |r| r["id"] }

    get api_bots_rooms_url, params: { query: "" }, headers: bot_headers(@bot.bot_key)
    assert_equal unfiltered, response.parsed_body.map { |r| r["id"] }
  end

  test "non-positive page values clamp to first page" do
    get api_bots_rooms_url, params: { per_page: 1, page: 1 }, headers: bot_headers(@bot.bot_key)
    first_page = response.parsed_body

    get api_bots_rooms_url, params: { per_page: 1, page: 0 }, headers: bot_headers(@bot.bot_key)
    assert_equal first_page, response.parsed_body

    get api_bots_rooms_url, params: { per_page: 1, page: -5 }, headers: bot_headers(@bot.bot_key)
    assert_equal first_page, response.parsed_body
  end

  test "joinable filter combines with query" do
    get api_bots_rooms_url, params: { joinable: true, query: "HQ" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    room_ids = response.parsed_body.map { |r| r["id"] }
    assert_includes room_ids, rooms(:hq).id
    assert_not_includes room_ids, rooms(:pets).id
  end

  test "index paginates and caps per_page" do
    Current.user = @bot
    5.times { |i| Rooms::Open.create_for({ name: "Page Room #{i}" }, users: @bot) }
    Current.reset

    get api_bots_rooms_url, params: { query: "Page Room", per_page: 2, page: 1 }, headers: bot_headers(@bot.bot_key)
    assert_response :success
    first_page = response.parsed_body
    assert_equal 2, first_page.size

    get api_bots_rooms_url, params: { query: "Page Room", per_page: 2, page: 2 }, headers: bot_headers(@bot.bot_key)
    assert_response :success
    second_page = response.parsed_body
    assert_equal 2, second_page.size

    assert_empty (first_page.map { |r| r["id"] } & second_page.map { |r| r["id"] })

    get api_bots_rooms_url, params: { per_page: 500 }, headers: bot_headers(@bot.bot_key)
    assert_operator response.parsed_body.size, :<=, 100
  end

  test "query is sanitized against LIKE wildcards" do
    Current.user = @bot
    Rooms::Open.create_for({ name: "Project Alpha" }, users: @bot)
    Rooms::Open.create_for({ name: "Project Beta" }, users: @bot)
    Current.reset

    # A bare % would otherwise match everything; sanitize_sql_like escapes it
    get api_bots_rooms_url, params: { query: "%Alpha" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    names = response.parsed_body.map { |r| r["name"] }
    assert_empty names, "literal % should not act as a wildcard, got #{names.inspect}"
  end

  # Room creation

  test "create an open room" do
    post api_bots_rooms_url,
      params: { name: "Bot Room", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal "Bot Room", json["name"]
    assert_equal "Open", json["type"]
  end

  test "create a closed room" do
    post api_bots_rooms_url,
      params: { name: "Secret Bot Room", type: "closed" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal "Secret Bot Room", json["name"]
    assert_equal "Closed", json["type"]
  end

  test "create room requires a name" do
    post api_bots_rooms_url,
      params: { type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "create room requires a valid type" do
    post api_bots_rooms_url,
      params: { name: "Bad Type", type: "direct" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "bot is auto-joined to created room" do
    post api_bots_rooms_url,
      params: { name: "My Room", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    room = Room.find(response.parsed_body["id"])
    assert room.users.include?(@bot)
  end

  test "bot is recorded as creator of room" do
    post api_bots_rooms_url,
      params: { name: "My Room", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    room = Room.find(response.parsed_body["id"])
    assert_equal @bot.id, room.creator_id
  end

  # Room update

  test "creator bot can rename room" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch api_bots_room_url(room),
      params: { name: "New Name" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal "New Name", response.parsed_body["name"]
    assert_equal "New Name", room.reload.name
  end

  test "non-creator bot cannot update room" do
    room = rooms(:watercooler) # created by david, not bender

    patch api_bots_room_url(room),
      params: { name: "Nope" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  test "update requires a name" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch api_bots_room_url(room),
      params: {},
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  # Room archive

  test "creator bot can archive room" do
    Current.user = @bot
    room = Rooms::Open.create_for({ name: "Doomed" }, users: @bot)
    Current.reset

    delete api_bots_room_url(room), headers: bot_headers(@bot.bot_key)

    assert_response :no_content
    assert_not room.reload.active?
  end

  test "non-creator bot cannot archive room" do
    room = rooms(:watercooler)

    delete api_bots_room_url(room), headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  # Auth

  test "session-authenticated user cannot use room management" do
    sign_in users(:david)

    post api_bots_rooms_url,
      params: { name: "Sneaky", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end
end
