require "test_helper"

class Accounts::Bots::ChannelPermissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @bot = users(:bender)
    @channel = channels(:designers)
  end

  test "index lists bot memberships and available channels" do
    get account_bot_channels_url(@bot)
    assert_response :ok
  end

  test "index requires admin" do
    sign_in :kevin
    get account_bot_channels_url(@bot)
    assert_redirected_to root_url
  end

  test "show for channel bot is in" do
    channel = channels(:watercooler) # bender has membership here
    get account_bot_channel_permission_url(@bot, channel)
    assert_response :ok
  end

  test "show for channel bot is not in" do
    get account_bot_channel_permission_url(@bot, @channel)
    assert_response :ok
  end

  test "create adds bot to channel with system message" do
    assert_difference -> { @bot.memberships.count } do
      post account_bot_channel_permission_url(@bot, @channel)
    end

    assert_redirected_to account_bot_channel_permission_url(@bot, @channel)
    assert @bot.member_of?(@channel)

    system_message = @channel.messages.last
    assert_match "added", system_message.body.to_plain_text
  end

  test "update changes involvement" do
    membership = @bot.memberships.find_by!(channel: channels(:watercooler))
    assert_equal "mentions", membership.involvement

    patch account_bot_channel_permission_url(@bot, channels(:watercooler)), params: { involvement: "nothing" }

    assert_redirected_to account_bot_channel_permission_url(@bot, channels(:watercooler))
    assert_equal "nothing", membership.reload.involvement
  end

  test "destroy removes bot from channel with system message" do
    channel = channels(:watercooler)

    delete account_bot_channel_permission_url(@bot, channel)

    assert_redirected_to account_bot_channel_permission_url(@bot, channel)
    assert_not @bot.reload.member_of?(channel)
  end
end
