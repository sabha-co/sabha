require "test_helper"

class ApplicationCable::BotConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "connects with valid bot_key" do
    bot = users(:bender)

    connect params: { bot_key: bot.bot_key }

    assert_equal bot, connection.current_user
  end

  test "rejects connection with invalid bot_key" do
    assert_reject_connection do
      connect params: { bot_key: "999-invalidtoken" }
    end
  end

  test "rejects connection with deactivated bot" do
    bot = users(:bender)
    bot.deactivate

    assert_reject_connection do
      connect params: { bot_key: bot.bot_key }
    end
  end
end
