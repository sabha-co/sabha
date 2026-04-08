require "test_helper"

class BotEventsChannelTest < ActionCable::Channel::TestCase
  test "bot subscribes successfully" do
    bot = users(:bender)
    stub_connection(current_user: bot)

    subscribe

    assert subscription.confirmed?
    assert_has_stream "bot_events:#{bot.id}"
  end

  test "rejects non-bot user" do
    stub_connection(current_user: users(:david))

    subscribe

    assert subscription.rejected?
  end

  test "rejects when no user" do
    stub_connection(current_user: nil)

    subscribe

    assert subscription.rejected?
  end

  test "receives broadcast event" do
    bot = users(:bender)
    stub_connection(current_user: bot)

    subscribe

    payload = { "event" => "message_created", "room" => { "id" => 1 } }
    ActionCable.server.broadcast("bot_events:#{bot.id}", payload)

    assert_broadcast_on("bot_events:#{bot.id}", payload)
  end
end
