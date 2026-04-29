require "test_helper"

class API::Bots::Messages::BoostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "create boost" do
    assert_difference -> { Boost.count }, 1 do
      post api_bots_room_message_boosts_url(@room, @message),
        params: "\u{1f389}",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "\u{1f389}", json["content"]
  end

  test "cannot create duplicate boost" do
    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created

    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :unprocessable_entity
  end

  test "destroy own boost" do
    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{2764}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    boost_id = response.parsed_body["id"]

    assert_difference -> { Boost.count }, -1 do
      delete api_bots_room_message_boost_url(@room, @message, boost_id), headers: bot_headers(@bot)
    end

    assert_response :no_content
  end

  test "returns 404 for room bot is not a member of" do
    post api_bots_room_message_boosts_url(rooms(:designers), messages(:first)),
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  # index — aggregated reactions
  # Cap-edge and sort-order behavior is exercised at the model level
  # (Message#reaction_summary). These tests cover the wire contract,
  # permissions, and N+1 prevention only.

  test "index returns the aggregated reactions wire shape" do
    @message.boosts.create!(content: "🚀", booster: users(:jason))
    @message.boosts.create!(content: "🚀", booster: users(:david))
    @message.boosts.create!(content: "❤️", booster: users(:jz))

    get api_bots_room_message_boosts_url(@room, @message), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal %w[reactions total truncated], json.keys
    assert_equal 3, json["total"]
    assert_equal false, json["truncated"]

    rocket = json["reactions"].find { |r| r["content"] == "🚀" }
    assert_equal %w[boosters content count truncated], rocket.keys.sort
    assert_equal 2, rocket["count"]
    assert_equal false, rocket["truncated"]
    assert_equal %w[id name], rocket["boosters"].first.keys.sort
    assert_equal [ users(:jason).id, users(:david).id ], rocket["boosters"].map { |b| b["id"] }
  end

  test "index returns empty envelope when no reactions exist" do
    get api_bots_room_message_boosts_url(@room, @message), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal [], json["reactions"]
    assert_equal 0, json["total"]
    assert_equal false, json["truncated"]
  end

  test "index does not N+1 on booster lookups as boost count grows" do
    %i[ jason david ].each { |h| @message.boosts.create!(content: "🚀", booster: users(h)) }
    baseline = count_sql_queries do
      get api_bots_room_message_boosts_url(@room, @message), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success

    %i[ jz rachel ].each { |h| @message.boosts.create!(content: "🚀", booster: users(h)) }
    doubled = count_sql_queries do
      get api_bots_room_message_boosts_url(@room, @message), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success

    assert_operator doubled, :<=, baseline + 1,
      "doubling boosts added #{doubled - baseline} queries — likely a per-booster N+1"
  end

  test "index 404s when bot cannot see the room" do
    get api_bots_room_message_boosts_url(rooms(:designers), messages(:first)),
        headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  test "index 404s when message is inactive" do
    @message.deactivate
    get api_bots_room_message_boosts_url(@room, @message), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Id-only boost ops (no room_id in URL).

  test "id-only create boost on any message the bot can see" do
    other_message = messages(:fourth) # creator: jz, room: watercooler — not bender's, but visible

    assert_difference -> { Boost.count }, 1 do
      post api_bots_message_boosts_url(other_message),
        params: "\u{1f389}",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    assert_equal "\u{1f389}", response.parsed_body["content"]
  end

  test "id-only create returns 404 with canonical envelope when bot can't see the room" do
    post api_bots_message_boosts_url(messages(:first)), # designers; bender has no membership
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "id-only destroy own boost" do
    post api_bots_message_boosts_url(@message),
      params: "\u{2764}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    boost_id = response.parsed_body["id"]

    assert_difference -> { Boost.count }, -1 do
      delete api_bots_message_boost_url(@message, boost_id), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
  end

  test "id-only boost create ignores a stray room_id query parameter from a stale client" do
    # Migration scenario: client mid-rebind still passes the stale parent room_id as a query
    # param. The path-params gate must ignore it, otherwise we'd 404 on thread messages.
    post api_bots_room_message_thread_url(@room, @message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "First reply" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    reply_id = response.parsed_body.dig("message", "id")

    post api_bots_message_boosts_url(message_id: reply_id, room_id: @room.id), # stale room_id
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :created
  end

  test "id-only destroy returns 404 with canonical envelope for someone else's boost" do
    other_boost = @message.boosts.create!(content: "\u{1f44d}", booster: users(:jason))

    delete api_bots_message_boost_url(@message, other_boost), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  private
    def count_sql_queries
      count = 0
      callback = ->(_, _, _, _, payload) {
        count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "RELEASE", "SAVEPOINT", "ROLLBACK")
      }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end
end
