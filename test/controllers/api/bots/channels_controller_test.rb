require "test_helper"

class API::Bots::ChannelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "lists channels the bot is a member of" do
    get api_bots_channels_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    channel_names = json.map { |r| r["name"] }
    assert_includes channel_names, channels(:watercooler).name
  end

  test "each channel includes id, name, type, and messages_url" do
    get api_bots_channels_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    channel = response.parsed_body.first
    assert channel["id"].present?
    assert channel["name"].present?
    assert channel["type"].present?
    assert channel["messages_url"].present?
  end

  test "excludes threads from channel list" do
    get api_bots_channels_url, headers: bot_headers(@bot.bot_key)

    assert_response :success
    types = response.parsed_body.map { |r| r["type"] }
    assert_not_includes types, "Thread"
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_channels_url, headers: bot_headers("999-invalidtoken")

    assert_redirected_to new_session_url
  end

  test "valid bot key works when SSO auth enabled" do
    original = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "sso"

    assert_no_difference -> { Session.count } do
      get api_bots_channels_url, headers: bot_headers(@bot.bot_key)
    end

    assert_response :success
    assert response.parsed_body.is_a?(Array)
    assert_nil session[:return_to_after_authenticating]
  ensure
    original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
  end

  # Joinable channels filter

  test "lists joinable open channels the bot is not in" do
    get api_bots_channels_url, params: { joinable: true }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)

    channel_ids = json.map { |r| r["id"] }
    # Bot is not in pets or hq (open channels), but IS in watercooler (closed)
    assert_includes channel_ids, channels(:pets).id
    assert_includes channel_ids, channels(:hq).id
    assert_not_includes channel_ids, channels(:watercooler).id
  end

  test "joinable filter only returns open channels the bot has not joined" do
    channels(:hq).accept_join!(@bot)

    get api_bots_channels_url, params: { joinable: true }, headers: bot_headers(@bot.bot_key)

    channel_ids = response.parsed_body.map { |r| r["id"] }
    joined_channel_ids = @bot.memberships.visible.pluck(:channel_id)
    assert_empty (channel_ids & joined_channel_ids), "joinable list must not contain channels the bot is in"
  end

  # Query and pagination

  test "index filters by query against channel name" do
    get api_bots_channels_url, params: { query: "Talk" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    names = response.parsed_body.map { |r| r["name"] }
    assert_includes names, channels(:watercooler).name # "All Talk"
    assert names.all? { |n| n.downcase.include?("talk") }, "expected only Talk-matching channels, got #{names.inspect}"
  end

  test "index returns no channels for non-matching query" do
    get api_bots_channels_url, params: { query: "ZzzNoSuchChannel" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_empty response.parsed_body
  end

  test "blank query returns the full set" do
    get api_bots_channels_url, headers: bot_headers(@bot.bot_key)
    unfiltered = response.parsed_body.map { |r| r["id"] }

    get api_bots_channels_url, params: { query: "" }, headers: bot_headers(@bot.bot_key)
    assert_equal unfiltered, response.parsed_body.map { |r| r["id"] }
  end

  test "non-positive page values clamp to first page" do
    get api_bots_channels_url, params: { per_page: 1, page: 1 }, headers: bot_headers(@bot.bot_key)
    first_page = response.parsed_body

    get api_bots_channels_url, params: { per_page: 1, page: 0 }, headers: bot_headers(@bot.bot_key)
    assert_equal first_page, response.parsed_body

    get api_bots_channels_url, params: { per_page: 1, page: -5 }, headers: bot_headers(@bot.bot_key)
    assert_equal first_page, response.parsed_body
  end

  test "joinable filter combines with query" do
    get api_bots_channels_url, params: { joinable: true, query: "HQ" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    channel_ids = response.parsed_body.map { |r| r["id"] }
    assert_includes channel_ids, channels(:hq).id
    assert_not_includes channel_ids, channels(:pets).id
  end

  test "index paginates and caps per_page" do
    Current.user = @bot
    5.times { |i| Channels::Open.create_for({ name: "Page Channel #{i}" }, users: @bot) }
    Current.reset

    get api_bots_channels_url, params: { query: "Page Channel", per_page: 2, page: 1 }, headers: bot_headers(@bot.bot_key)
    assert_response :success
    first_page = response.parsed_body
    assert_equal 2, first_page.size

    get api_bots_channels_url, params: { query: "Page Channel", per_page: 2, page: 2 }, headers: bot_headers(@bot.bot_key)
    assert_response :success
    second_page = response.parsed_body
    assert_equal 2, second_page.size

    assert_empty (first_page.map { |r| r["id"] } & second_page.map { |r| r["id"] })

    get api_bots_channels_url, params: { per_page: 500 }, headers: bot_headers(@bot.bot_key)
    assert_operator response.parsed_body.size, :<=, 100
  end

  test "query is sanitized against LIKE wildcards" do
    Current.user = @bot
    Channels::Open.create_for({ name: "Project Alpha" }, users: @bot)
    Channels::Open.create_for({ name: "Project Beta" }, users: @bot)
    Current.reset

    # A bare % would otherwise match everything; sanitize_sql_like escapes it
    get api_bots_channels_url, params: { query: "%Alpha" }, headers: bot_headers(@bot.bot_key)

    assert_response :success
    names = response.parsed_body.map { |r| r["name"] }
    assert_empty names, "literal % should not act as a wildcard, got #{names.inspect}"
  end

  # Channel creation

  test "create an open channel" do
    post api_bots_channels_url,
      params: { name: "Bot Channel", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal "Bot Channel", json["name"]
    assert_equal "Open", json["type"]
  end

  test "create a closed channel" do
    post api_bots_channels_url,
      params: { name: "Secret Bot Channel", type: "closed" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal "Secret Bot Channel", json["name"]
    assert_equal "Closed", json["type"]
  end

  test "create channel requires a name" do
    post api_bots_channels_url,
      params: { type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "create channel requires a valid type" do
    post api_bots_channels_url,
      params: { name: "Bad Type", type: "direct" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  test "bot is auto-joined to created channel" do
    post api_bots_channels_url,
      params: { name: "My Channel", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    channel = Channel.find(response.parsed_body["id"])
    assert channel.users.include?(@bot)
  end

  test "bot is recorded as creator of channel" do
    post api_bots_channels_url,
      params: { name: "My Channel", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    channel = Channel.find(response.parsed_body["id"])
    assert_equal @bot.id, channel.creator_id
  end

  # Channel update

  test "creator bot can rename channel" do
    Current.user = @bot
    channel = Channels::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch api_bots_channel_url(channel),
      params: { name: "New Name" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :success
    assert_equal "New Name", response.parsed_body["name"]
    assert_equal "New Name", channel.reload.name
  end

  test "non-creator bot cannot update channel" do
    channel = channels(:watercooler) # created by david, not bender

    patch api_bots_channel_url(channel),
      params: { name: "Nope" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  test "update requires a name" do
    Current.user = @bot
    channel = Channels::Open.create_for({ name: "Old Name" }, users: @bot)
    Current.reset

    patch api_bots_channel_url(channel),
      params: {},
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
  end

  # Channel archive

  test "creator bot can archive channel" do
    Current.user = @bot
    channel = Channels::Open.create_for({ name: "Doomed" }, users: @bot)
    Current.reset

    delete api_bots_channel_url(channel), headers: bot_headers(@bot.bot_key)

    assert_response :no_content
    assert_not channel.reload.active?
  end

  test "non-creator bot cannot archive channel" do
    channel = channels(:watercooler)

    delete api_bots_channel_url(channel), headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  # Auth

  test "session-authenticated user cannot use channel management" do
    sign_in users(:david)

    post api_bots_channels_url,
      params: { name: "Sneaky", type: "open" },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end
end
