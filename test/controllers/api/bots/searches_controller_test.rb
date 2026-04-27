require "test_helper"

class API::Bots::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler) # bender is a member
    @other_room = rooms(:designers) # bender is NOT a member
  end

  # Envelope shape

  test "search returns results, has_more, and next_cursor envelope keys" do
    create_searchable_messages(@room, count: 1)

    get api_bots_search_url(q: "findme"), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.key?("results"), "expected 'results' key, got #{json.inspect}"
    assert json.key?("has_more"), "expected 'has_more' key, got #{json.inspect}"
    assert json.key?("next_cursor"), "expected 'next_cursor' key, got #{json.inspect}"
    assert json["results"].is_a?(Array)
    assert_includes [ true, false ], json["has_more"]
  end

  test "result objects expose id, creator, body, room, created_at" do
    create_searchable_messages(@room, count: 1)

    get api_bots_search_url(q: "findme"), headers: bot_headers(@bot.bot_key)

    msg = response.parsed_body["results"].first
    assert msg["id"].present?
    assert_equal %w[id name], msg["creator"].keys.sort
    assert_equal %w[html plain], msg["body"].keys.sort
    assert_equal %w[id name], msg["room"].keys.sort
    assert msg["created_at"].present?
  end

  # Validation

  test "search requires q param" do
    get api_bots_search_url(), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "search with blank q returns error" do
    get api_bots_search_url(q: ""), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_search_url(q: "test"), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  # has_more truncation signal

  test "has_more is false and next_cursor is nil when results fit within limit" do
    create_searchable_messages(@room, count: 2)

    get api_bots_search_url(q: "findme", limit: 10), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal false, json["has_more"]
    assert_nil json["next_cursor"]
    assert_equal 2, json["results"].size
  end

  test "has_more is true and next_cursor is set when more results exist" do
    create_searchable_messages(@room, count: 5)

    get api_bots_search_url(q: "findme", limit: 2), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal true, json["has_more"]
    assert_equal 2, json["results"].size

    # next_cursor is the created_at of the oldest (last) result in newest-first ordering
    expected_cursor = Time.iso8601(json["results"].last["created_at"]).iso8601
    assert_equal expected_cursor, json["next_cursor"]
  end

  # Limit cap

  test "limit clamps above MAX_LIMIT" do
    create_searchable_messages(@room, count: 1)

    get api_bots_search_url(q: "findme", limit: 5_000), headers: bot_headers(@bot.bot_key)

    assert_response :success
    # Cap is silent — caller asked for 5000, server enforces 200.
    # Verify by checking has_more remains false (1 result ≤ 200) without erroring.
    assert_equal false, response.parsed_body["has_more"]
  end

  test "limit clamps below 1 to 1" do
    create_searchable_messages(@room, count: 3)

    get api_bots_search_url(q: "findme", limit: 0), headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal 1, response.parsed_body["results"].size
  end

  # Scoping by room

  test "results filter by room_ids" do
    create_searchable_messages(@room, count: 2)
    other_room = Rooms::Open.create!(name: "Bot Side Room", creator: users(:david))
    Membership.create!(user: @bot, room: other_room, involvement: :everything)
    create_searchable_messages(other_room, count: 3)

    get api_bots_search_url(q: "findme", room_ids: [ other_room.id ]),
        headers: bot_headers(@bot.bot_key)

    assert_response :success
    room_ids = response.parsed_body["results"].map { |r| r["room"]["id"] }
    assert_equal [ other_room.id ], room_ids.uniq
  end

  test "results never include messages from rooms bot cannot reach" do
    # Create a message in designers (bender is not a member)
    @other_room.messages.create!(creator: users(:david), body: "findme stranger")

    get api_bots_search_url(q: "findme"), headers: bot_headers(@bot.bot_key)

    assert_response :success
    room_ids = response.parsed_body["results"].map { |r| r["room"]["id"] }
    assert_not_includes room_ids, @other_room.id
  end

  test "passing an unreachable room_id returns no results, not 403" do
    create_searchable_messages(@room, count: 1)

    get api_bots_search_url(q: "findme", room_ids: [ @other_room.id ]),
        headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_empty response.parsed_body["results"]
  end

  # Scoping by author

  test "results filter by author_ids" do
    create_searchable_messages(@room, count: 2, creator: users(:david))
    create_searchable_messages(@room, count: 2, creator: users(:jason))

    get api_bots_search_url(q: "findme", author_ids: [ users(:david).id ]),
        headers: bot_headers(@bot.bot_key)

    assert_response :success
    creator_ids = response.parsed_body["results"].map { |r| r["creator"]["id"] }
    assert_equal [ users(:david).id ], creator_ids.uniq
  end

  # Time filters

  test "created_before excludes messages newer than the cutoff" do
    older = create_searchable_messages(@room, count: 1).first
    older.update_columns(created_at: 2.days.ago)
    create_searchable_messages(@room, count: 1) # newer, "now"

    cutoff = 1.day.ago.iso8601
    get api_bots_search_url(q: "findme", before: cutoff), headers: bot_headers(@bot.bot_key)

    assert_response :success
    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ older.id ], ids
  end

  test "created_after excludes messages older than the cutoff" do
    older = create_searchable_messages(@room, count: 1).first
    older.update_columns(created_at: 2.days.ago)
    newer = create_searchable_messages(@room, count: 1).first

    cutoff = 1.day.ago.iso8601
    get api_bots_search_url(q: "findme", after: cutoff), headers: bot_headers(@bot.bot_key)

    assert_response :success
    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ newer.id ], ids
  end

  test "unparseable before timestamp returns 422" do
    get api_bots_search_url(q: "findme", before: "not-a-date"),
        headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
    assert_match(/before/i, response.parsed_body["error"])
  end

  test "unparseable after timestamp returns 422" do
    get api_bots_search_url(q: "findme", after: "yesterday"),
        headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
    assert_match(/after/i, response.parsed_body["error"])
  end

  # Ordering and cursor pagination

  test "results come back newest-first" do
    older = create_searchable_messages(@room, count: 1).first
    older.update_columns(created_at: 2.hours.ago)
    middle = create_searchable_messages(@room, count: 1).first
    middle.update_columns(created_at: 1.hour.ago)
    newest = create_searchable_messages(@room, count: 1).first

    get api_bots_search_url(q: "findme"), headers: bot_headers(@bot.bot_key)

    ids = response.parsed_body["results"].map { |r| r["id"] }
    assert_equal [ newest.id, middle.id, older.id ], ids
  end

  test "passing next_cursor as before continues pagination without overlap" do
    # Create 4 messages with distinct timestamps so cursor is unambiguous
    msgs = Array.new(4) do |i|
      m = create_searchable_messages(@room, count: 1).first
      m.update_columns(created_at: (4 - i).hours.ago)
      m
    end
    expected_order_newest_first = msgs.reverse.map(&:id)

    get api_bots_search_url(q: "findme", limit: 2), headers: bot_headers(@bot.bot_key)
    page_one = response.parsed_body
    cursor = page_one["next_cursor"]
    assert_not_nil cursor

    get api_bots_search_url(q: "findme", limit: 2, before: cursor),
        headers: bot_headers(@bot.bot_key)
    page_two = response.parsed_body

    page_one_ids = page_one["results"].map { |r| r["id"] }
    page_two_ids = page_two["results"].map { |r| r["id"] }

    assert_empty (page_one_ids & page_two_ids), "pages must not overlap"
    assert_equal expected_order_newest_first, page_one_ids + page_two_ids
    assert_equal false, page_two["has_more"]
    assert_nil page_two["next_cursor"]
  end

  # N+1 prevention

  test "rendering many results does not trigger per-row creator or room queries" do
    create_searchable_messages(@room, count: 5)
    baseline_count = count_sql_queries do
      get api_bots_search_url(q: "findme", limit: 5), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success
    assert_equal 5, response.parsed_body["results"].size

    create_searchable_messages(@room, count: 5)
    doubled_count = count_sql_queries do
      get api_bots_search_url(q: "findme", limit: 10), headers: bot_headers(@bot.bot_key)
    end
    assert_response :success
    assert_equal 10, response.parsed_body["results"].size

    # Rendering 2x rows must not 2x the queries — that would mean a per-row fetch.
    assert_operator doubled_count, :<=, baseline_count + 2,
      "rendering 2x rows added #{doubled_count - baseline_count} queries — likely an N+1 regression"
  end

  private
    def create_searchable_messages(room, count:, creator: nil)
      creator ||= room.users.where.not(id: @bot.id).first || users(:david)
      Array.new(count) { |i| room.messages.create!(creator: creator, body: "findme token #{i}") }
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
