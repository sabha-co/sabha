require "test_helper"

class API::Bots::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  # Join channel

  test "bot can join an open channel" do
    channel = channels(:hq) # open channel, bot is not a member

    post api_bots_channel_membership_url(channel), headers: bot_headers(@bot.bot_key)

    assert_response :created
    json = response.parsed_body
    assert_equal channel.id, json["id"]
    assert channel.reload.users.include?(@bot)
  end

  test "bot cannot join a closed channel" do
    channel = channels(:designers) # closed channel

    post api_bots_channel_membership_url(channel), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 for nonexistent channel" do
    post api_bots_channel_membership_url(999999), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Leave channel

  test "bot can leave a channel" do
    channel = channels(:watercooler) # bot is a member

    delete api_bots_channel_membership_url(channel), headers: bot_headers(@bot.bot_key)

    assert_response :no_content
  end

  test "bot cannot leave a direct message channel" do
    Current.user = @bot
    dm = Channels::Direct.find_or_create_for([ @bot, users(:david) ])
    Current.reset

    delete api_bots_channel_membership_url(dm), headers: bot_headers(@bot.bot_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "returns 404 when leaving channel bot is not in" do
    delete api_bots_channel_membership_url(channels(:designers)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Auth

  test "invalid bot key redirects to sign in" do
    post api_bots_channel_membership_url(channels(:hq)), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  test "session-authenticated user cannot use bot join" do
    sign_in users(:david)

    post api_bots_channel_membership_url(channels(:hq)), headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end
end
