require "test_helper"

class API::Bots::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler) # bender is a member
    @other_room = rooms(:designers) # bender is NOT a member
  end

  # Envelope shape

  test "search returns results array and has_more flag" do
    create_searchable_messages(@room, count: 1)

    get api_bots_search_url(q: "findme"), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.key?("results"), "expected envelope with 'results' key, got #{json.inspect}"
    assert json.key?("has_more"), "expected envelope with 'has_more' key, got #{json.inspect}"
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

  test "has_more is false when results fit within limit" do
    create_searchable_messages(@room, count: 2)

    get api_bots_search_url(q: "findme", limit: 10), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal false, json["has_more"]
    assert_equal 2, json["results"].size
  end

  test "has_more is true and exactly limit results returned when more exist" do
    create_searchable_messages(@room, count: 5)

    get api_bots_search_url(q: "findme", limit: 2), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert_equal true, json["has_more"]
    assert_equal 2, json["results"].size
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

  # Pagination

  test "page advances past previously seen results" do
    create_searchable_messages(@room, count: 4)

    get api_bots_search_url(q: "findme", limit: 2, page: 1), headers: bot_headers(@bot.bot_key)
    first_page_ids = response.parsed_body["results"].map { |r| r["id"] }

    get api_bots_search_url(q: "findme", limit: 2, page: 2), headers: bot_headers(@bot.bot_key)
    second_page_ids = response.parsed_body["results"].map { |r| r["id"] }

    assert_equal 2, first_page_ids.size
    assert_equal 2, second_page_ids.size
    assert_empty (first_page_ids & second_page_ids)
  end

  test "non-positive page values clamp to first page" do
    create_searchable_messages(@room, count: 3)

    get api_bots_search_url(q: "findme", limit: 1, page: 1), headers: bot_headers(@bot.bot_key)
    expected = response.parsed_body["results"]

    get api_bots_search_url(q: "findme", limit: 1, page: 0), headers: bot_headers(@bot.bot_key)
    assert_equal expected, response.parsed_body["results"]

    get api_bots_search_url(q: "findme", limit: 1, page: -3), headers: bot_headers(@bot.bot_key)
    assert_equal expected, response.parsed_body["results"]
  end

  test "page clamps to MAX_PAGE to bound deep-offset work" do
    create_searchable_messages(@room, count: 1)

    over_max = API::Bots::SearchesController::MAX_PAGE + 100
    get api_bots_search_url(q: "findme", limit: 1, page: over_max), headers: bot_headers(@bot.bot_key)
    over_response = response.parsed_body

    get api_bots_search_url(q: "findme", limit: 1, page: API::Bots::SearchesController::MAX_PAGE),
        headers: bot_headers(@bot.bot_key)
    capped_response = response.parsed_body

    assert_equal capped_response, over_response
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
