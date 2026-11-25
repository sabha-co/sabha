require "test_helper"

class API::Bots::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @channel = channels(:watercooler)
  end

  test "list channel members" do
    get api_bots_channel_members_url(@channel), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)
    assert json.any? { |m| m["id"] == @bot.id }

    member = json.first
    assert member["id"].present?
    assert member["name"].present?
    assert member["role"].present?
  end

  test "returns 404 for channel bot is not a member of" do
    get api_bots_channel_members_url(channels(:designers)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  test "returns 404 for a sub-channel the bot can no longer view after leaving the parent" do
    thread = nil
    Current.set(user: @bot) do
      channel = Channels::Closed.create_for({ name: "Bot Parent" }, users: @bot)
      channel.add_member!(users(:david), actor: @bot) # keep a human so the channel survives
      parent = channel.messages.create!(body: "topic", creator: @bot)
      thread = Channels::Thread.find_or_create_for(parent, creator: @bot)
      channel.remove_member!(@bot, actor: users(:david))
      ThreadFollowCleanupJob.perform_now(channel: channel, user: @bot)
    end
    assert Membership.exists?(channel_id: thread.id, user_id: @bot.id, active: true),
      "precondition: the bot keeps a silenced-but-active thread row"

    get api_bots_channel_members_url(thread), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_channel_members_url(@channel), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  # Add member

  test "creator bot can add a member" do
    Current.user = @bot
    channel = Channels::Closed.create_for({ name: "Bot's Channel" }, users: @bot)
    Current.reset

    post api_bots_channel_members_url(channel),
      params: { user_id: users(:david).id },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    assert_equal users(:david).id, response.parsed_body["id"]
    assert channel.users.include?(users(:david))
  end

  test "non-creator bot cannot add members" do
    post api_bots_channel_members_url(@channel),
      params: { user_id: users(:kevin).id },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  test "adding nonexistent user returns 404" do
    Current.user = @bot
    channel = Channels::Closed.create_for({ name: "Bot's Channel" }, users: @bot)
    Current.reset

    post api_bots_channel_members_url(channel),
      params: { user_id: 999999 },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Remove member

  test "creator bot can remove a member" do
    Current.user = @bot
    channel = Channels::Closed.create_for({ name: "Bot's Channel" }, users: @bot)
    Current.reset
    channel.add_member!(users(:david), actor: @bot)

    delete api_bots_channel_member_url(channel, users(:david)), headers: bot_headers(@bot)

    assert_response :no_content
    assert_not channel.reload.users.include?(users(:david))
  end

  test "non-creator bot cannot remove members" do
    delete api_bots_channel_member_url(@channel, users(:david)), headers: bot_headers(@bot)

    assert_response :forbidden
  end

  test "cannot remove last member" do
    Current.user = @bot
    channel = Channels::Closed.create_for({ name: "Solo Bot" }, users: @bot)
    Current.reset

    delete api_bots_channel_member_url(channel, @bot), headers: bot_headers(@bot)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end
end
