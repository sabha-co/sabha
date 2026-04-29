require "test_helper"

class API::Bots::MessagesByIdControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler) # bender has membership here
    @message = messages(:bender_message) # bender's own message in watercooler
  end

  test "PATCH succeeds for the bot's own message" do
    patch api_bots_message_url(@message),
      params: "Updated text",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    json = response.parsed_body
    assert_equal @message.id, json["id"]
    assert_equal "Updated text", @message.reload.plain_text_body
  end

  test "PATCH returns 403 for a message owned by another user" do
    other_message = messages(:fourth) # creator: jz, room: watercooler

    patch api_bots_message_url(other_message),
      params: "Hacked",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :forbidden
  end

  test "PATCH returns 404 with canonical envelope for a message in a room the bot can't access" do
    other_message = messages(:first) # in designers; bender has no membership

    patch api_bots_message_url(other_message),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "PATCH returns 404 with canonical envelope for a nonexistent message id" do
    patch api_bots_message_url(id: 999_999_999),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "PATCH succeeds for a message in a thread the bot can see, without passing the thread room id" do
    # Bot creates a thread off its own message; the first reply lives in the new thread room
    post api_bots_room_message_thread_url(@room, @message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "First reply" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    reply_id = response.parsed_body.dig("message", "id")

    # Now PATCH the reply via the id-only route — the caller never reads response["thread"]["id"]
    patch api_bots_message_url(id: reply_id),
      params: "Updated reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    assert_equal "Updated reply", Message.find(reply_id).plain_text_body
  end

  test "PATCH returns 404 with canonical envelope for a soft-deleted message" do
    @message.deactivate

    patch api_bots_message_url(@message),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "DELETE deactivates the message" do
    assert_difference -> { Message.active.count }, -1 do
      delete api_bots_message_url(@message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
    assert_not @message.reload.active?
  end

  test "DELETE returns 403 for a message owned by another user" do
    other_message = messages(:fourth) # creator: jz, room: watercooler

    assert_no_difference -> { Message.active.count } do
      delete api_bots_message_url(other_message), headers: bot_headers(@bot.bot_key)
    end

    assert_response :forbidden
  end
end
