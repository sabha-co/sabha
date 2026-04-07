require "test_helper"

class Messages::DeletionsByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "delete own message" do
    assert_difference -> { Message.active.count }, -1 do
      delete room_bot_message_delete_url(@room, @bot.bot_key, @message)
    end

    assert_response :no_content
    assert_not @message.reload.active?
  end

  test "cannot delete another user's message" do
    other_message = messages(:fourth)

    assert_no_difference -> { Message.active.count } do
      delete room_bot_message_delete_url(@room, @bot.bot_key, other_message)
    end

    assert_response :forbidden
  end

  test "returns 404 for room bot is not a member of" do
    delete room_bot_message_delete_url(rooms(:designers), @bot.bot_key, messages(:first))

    assert_response :not_found
  end
end
