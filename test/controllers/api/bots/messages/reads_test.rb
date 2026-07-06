require "test_helper"

class API::Bots::Messages::ReadsTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler) # bender is a member
    @other_room = rooms(:designers) # bender is NOT a member
  end

  # Fresh room with bender as a member — used by tests that need a controlled
  # message set without fixture noise. Strips the "room_created" / "member_joined"
  # system events so the room starts empty from the API's perspective.
  def fresh_room
    @fresh_room ||= begin
      room = Rooms::Open.create!(name: "Bot Read Test Room", creator: users(:david))
      Membership.create!(user: @bot, room: room, involvement: :everything)
      room.messages.destroy_all
      room
    end
  end

  # Envelope shape

  test "index returns results, has_more, and next_cursor envelope keys" do
    @room.messages.create!(creator: users(:david), body: "hello")

    get api_bots_room_messages_url(@room), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.key?("results"), "expected 'results' key, got #{json.inspect}"
    assert json.key?("has_more")
    assert json.key?("next_cursor")
    assert json["results"].is_a?(Array)
    assert_includes [ true, false ], json["has_more"]
  end

  test "index result objects expose id, creator, body, attachment, created_at — and not mentionees or has_attachment" do
    @room.messages.create!(creator: users(:david), body: "hello")

    get api_bots_room_messages_url(@room), headers: bot_headers(@bot.bot_key)

    msg = response.parsed_body["results"].first
    assert msg["id"].present?
    assert_equal %w[id name], msg["creator"].keys.sort
    assert_equal %w[html plain], msg["body"].keys.sort
    assert msg.key?("attachment")
    assert msg["created_at"].present?

    assert_not msg.key?("mentionees"), "index intentionally omits mentionees to avoid the pre-existing per-message N+1"
    assert_not msg.key?("has_attachment"), "has_attachment is redundant with attachment? null check"
  end

  test "show response includes mentionees field" do
    message = messages(:bender_message)

    get api_bots_message_url(message), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.key?("mentionees"), "show retains mentionees — single-row N+1 is bounded"
    assert_equal message.id, json["id"]
    assert_equal %w[id name], json["creator"].keys.sort
  end

  # Permissions

  test "index 404s when bot is not in the room" do
    get api_bots_room_messages_url(@other_room), headers: bot_headers(@bot.bot_key)
    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_room_messages_url(@room), headers: bot_headers("999-invalidtoken")
    assert_redirected_to new_session_url
  end

  test "show 404s for nonexistent message" do
    get api_bots_message_url(999999), headers: bot_headers(@bot.bot_key)
    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "show 404s for message in room bot is not in" do
    message = @other_room.messages.create!(creator: users(:david), body: "test")
    get api_bots_message_url(message), headers: bot_headers(@bot.bot_key)
    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "show 404s for a message in a sub-room the bot left the parent of" do
    thread = reply = nil
    Current.set(user: @bot) do
      room = Rooms::Closed.create_for({ name: "Bot Thread Parent", creator: @bot }, users: @bot)
      room.add_member!(users(:david), actor: @bot) # keep a human so removal is allowed
      parent = room.messages.create!(body: "topic", creator: @bot)
      thread = Rooms::Thread.find_or_create_for(parent, creator: @bot)
      reply = thread.messages.create!(body: "secret", creator: @bot)
      room.remove_member!(@bot, actor: users(:david))
      ThreadFollowCleanupJob.perform_now(room: room, user: @bot)
    end
    assert Membership.exists?(room_id: thread.id, user_id: @bot.id, active: true),
      "precondition: the bot keeps a silenced-but-active thread row"

    get api_bots_message_url(reply), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # has_more truncation signal

  test "has_more is false and next_cursor is nil when results fit within limit" do
    create_messages(fresh_room, count: 2)

    get api_bots_room_messages_url(fresh_room, limit: 10), headers: bot_headers(@bot.bot_key)

    json = response.parsed_body
    assert_equal false, json["has_more"]
    assert_nil json["next_cursor"]
    assert_equal 2, json["results"].size
  end

  test "has_more is true and next_cursor is composite (iso|id) when more results exist" do
    create_messages(fresh_room, count: 5)

    get api_bots_room_messages_url(fresh_room, limit: 2), headers: bot_headers(@bot.bot_key)

    json = response.parsed_body
    assert_equal true, json["has_more"]
    assert_equal 2, json["results"].size

    last = json["results"].last
    expected = "#{Time.iso8601(last["created_at"]).iso8601}|#{last["id"]}"
    assert_equal expected, json["next_cursor"]
  end

  # Limit cap

  test "limit clamps above MAX_LIMIT" do
    get api_bots_room_messages_url(@room, limit: 5_000), headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_operator response.parsed_body["results"].size, :<=, 200
  end

  test "limit clamps below 1 to 1" do
    create_messages(fresh_room, count: 3)

    get api_bots_room_messages_url(fresh_room, limit: 0), headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal 1, response.parsed_body["results"].size
  end

  # Time filters

  test "after lower-bound excludes messages older than the cutoff" do
    older = create_messages(fresh_room, count: 1).first
    older.update_columns(created_at: 2.days.ago)
    newer = create_messages(fresh_room, count: 1).first

    get api_bots_room_messages_url(fresh_room, after: 1.day.ago.iso8601), headers: bot_headers(@bot.bot_key)

    assert_response :success
    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ newer.id ], ids
  end

  test "plain ISO timestamp before still works as a filter (back-compat)" do
    older = create_messages(fresh_room, count: 1).first
    older.update_columns(created_at: 2.days.ago)
    create_messages(fresh_room, count: 1) # newer, "now"

    get api_bots_room_messages_url(fresh_room, before: 1.day.ago.iso8601), headers: bot_headers(@bot.bot_key)

    assert_response :success
    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ older.id ], ids
  end

  test "unparseable before timestamp returns 422" do
    get api_bots_room_messages_url(@room, before: "not-a-date"), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
    assert_match(/before/i, response.parsed_body["error"])
  end

  test "unparseable after timestamp returns 422" do
    get api_bots_room_messages_url(@room, after: "yesterday"), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
    assert_match(/after/i, response.parsed_body["error"])
  end

  # Ordering and cursor pagination

  test "results come back newest-first" do
    older = create_messages(fresh_room, count: 1).first
    older.update_columns(created_at: 2.hours.ago)
    middle = create_messages(fresh_room, count: 1).first
    middle.update_columns(created_at: 1.hour.ago)
    newest = create_messages(fresh_room, count: 1).first

    get api_bots_room_messages_url(fresh_room), headers: bot_headers(@bot.bot_key)

    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ newest.id, middle.id, older.id ], ids
  end

  test "composite cursor is stable across same-second timestamp ties" do
    shared_time = 1.hour.ago.change(usec: 0)
    msgs = Array.new(3) { create_messages(fresh_room, count: 1).first }
    msgs.each { |m| m.update_columns(created_at: shared_time) }
    expected_ids = msgs.map(&:id).sort.reverse # id DESC tiebreaker

    get api_bots_room_messages_url(fresh_room, limit: 2), headers: bot_headers(@bot.bot_key)
    page_one = response.parsed_body
    cursor = page_one["next_cursor"]
    assert_not_nil cursor

    get api_bots_room_messages_url(fresh_room, limit: 2, before: cursor), headers: bot_headers(@bot.bot_key)
    page_two = response.parsed_body

    page_one_ids = page_one["results"].map { |r| r["id"] }
    page_two_ids = page_two["results"].map { |r| r["id"] }
    assert_empty (page_one_ids & page_two_ids), "tied-timestamp rows must not overlap"
    assert_equal expected_ids, page_one_ids + page_two_ids
  end

  test "after lower-bound composes with cursor across pages" do
    out_of_window = create_messages(fresh_room, count: 1).first
    out_of_window.update_columns(created_at: 10.days.ago)

    in_window = Array.new(4) do |i|
      m = create_messages(fresh_room, count: 1).first
      m.update_columns(created_at: (4 - i).hours.ago)
      m
    end
    expected_order = in_window.reverse.map(&:id)

    lower_bound = 1.day.ago.iso8601

    get api_bots_room_messages_url(fresh_room, after: lower_bound, limit: 2), headers: bot_headers(@bot.bot_key)
    page_one = response.parsed_body
    cursor = page_one["next_cursor"]

    get api_bots_room_messages_url(fresh_room, after: lower_bound, limit: 2, before: cursor),
        headers: bot_headers(@bot.bot_key)
    page_two = response.parsed_body

    seen = page_one["results"].map { |r| r["id"] } + page_two["results"].map { |r| r["id"] }
    assert_equal expected_order, seen
    assert_not_includes seen, out_of_window.id
  end

  test "passing next_cursor as before continues pagination without overlap" do
    msgs = Array.new(4) do |i|
      m = create_messages(fresh_room, count: 1).first
      m.update_columns(created_at: (4 - i).hours.ago)
      m
    end
    expected_order = msgs.reverse.map(&:id)

    get api_bots_room_messages_url(fresh_room, limit: 2), headers: bot_headers(@bot.bot_key)
    page_one = response.parsed_body
    cursor = page_one["next_cursor"]
    assert_not_nil cursor

    get api_bots_room_messages_url(fresh_room, limit: 2, before: cursor), headers: bot_headers(@bot.bot_key)
    page_two = response.parsed_body

    page_one_ids = page_one["results"].map { |r| r["id"] }
    page_two_ids = page_two["results"].map { |r| r["id"] }

    assert_empty (page_one_ids & page_two_ids)
    assert_equal expected_order, page_one_ids + page_two_ids
    assert_equal false, page_two["has_more"]
    assert_nil page_two["next_cursor"]
  end

  # N+1 prevention

  test "rendering many results does not trigger per-row creator or body queries" do
    create_messages(fresh_room, count: 5)
    baseline = count_sql_queries do
      get api_bots_room_messages_url(fresh_room, limit: 5), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success
    assert_equal 5, response.parsed_body["results"].size

    create_messages(fresh_room, count: 5)
    doubled = count_sql_queries do
      get api_bots_room_messages_url(fresh_room, limit: 10), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success
    assert_equal 10, response.parsed_body["results"].size

    assert_operator doubled, :<=, baseline + 2,
      "doubling rows added #{doubled - baseline} queries — likely an N+1 regression"
  end

  private
    def create_messages(room, count:)
      Array.new(count) { |i| room.messages.create!(creator: users(:david), body: "msg #{i}") }
    end

    def count_sql_queries
      count = 0
      callback = ->(_, _, _, _, payload) {
        count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "RELEASE", "SAVEPOINT", "ROLLBACK")
      }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end
end
