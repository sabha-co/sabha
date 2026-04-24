require "test_helper"

class Messages::DeletionsByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "delete own message" do
    assert_difference -> { Message.active.count }, -1 do
      delete api_bots_room_message_url(@room, @message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
    assert_not @message.reload.active?
  end

  test "cannot delete another user's message" do
    other_message = messages(:fourth)

    assert_no_difference -> { Message.active.count } do
      delete api_bots_room_message_url(@room, other_message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :forbidden
  end

  test "returns 404 for room bot is not a member of" do
    delete api_bots_room_message_url(rooms(:designers), messages(:first)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end
end
