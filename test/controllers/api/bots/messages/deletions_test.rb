require "test_helper"

class API::Bots::Messages::DeletionsTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @message = messages(:bender_message)
  end

  test "delete own message" do
    assert_difference -> { Message.active.count }, -1 do
      delete api_bots_message_url(@message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
    assert_not @message.reload.active?
  end

  test "cannot delete another user's message" do
    other_message = messages(:fourth)

    assert_no_difference -> { Message.active.count } do
      delete api_bots_message_url(other_message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :forbidden
  end

  test "returns 404 with canonical envelope for a message in a room the bot can't see" do
    delete api_bots_message_url(messages(:first)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "id-only delete resolves into thread rooms without the caller passing the thread room id" do
    # Bot creates a thread off its own message via inline parent_message_id;
    # the first reply lives in a brand-new thread room.
    post api_bots_room_messages_url(@message.room, parent_message_id: @message.id),
      params: "First reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    reply_id = response.parsed_body["id"]

    assert_difference -> { Message.active.count }, -1 do
      delete api_bots_message_url(reply_id), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
  end
end
