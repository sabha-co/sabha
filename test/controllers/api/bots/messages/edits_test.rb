require "test_helper"

class API::Bots::Messages::EditsTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "edit own message" do
    patch api_bots_room_message_url(@room, @message),
      params: "Updated text",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    json = response.parsed_body
    assert_equal @message.id, json["id"]
    assert_equal "Updated text", @message.reload.plain_text_body
  end

  test "cannot edit another user's message" do
    other_message = messages(:fourth) # created by david

    patch api_bots_room_message_url(@room, other_message),
      params: "Hacked",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :forbidden
  end

  test "returns 404 for room bot is not a member of" do
    patch api_bots_room_message_url(rooms(:designers), messages(:first)),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    patch api_bots_room_message_url(@room, @message),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers("999-invalid"))

    assert_redirected_to new_session_url
  end

  # Id-only edit (no room_id in URL) — preferred shape for streaming clients.

  test "id-only edit own message" do
    patch api_bots_message_url(@message),
      params: "Updated text",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    assert_equal @message.id, response.parsed_body["id"]
    assert_equal "Updated text", @message.reload.plain_text_body
  end

  test "id-only cannot edit another user's message" do
    other_message = messages(:fourth) # creator: jz, room: watercooler

    patch api_bots_message_url(other_message),
      params: "Hacked",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :forbidden
  end

  test "id-only returns 404 with canonical envelope for a message in a room the bot can't see" do
    patch api_bots_message_url(messages(:first)), # in designers; bender has no membership
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "id-only returns 404 with canonical envelope for a nonexistent message id" do
    patch api_bots_message_url(id: 999_999_999),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "id-only returns 404 for a soft-deleted message" do
    @message.deactivate

    patch api_bots_message_url(@message),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  test "id-only edit ignores a stray room_id query parameter from a stale client" do
    # Migration scenario: a client carrying over an old `room_id` from before the thread rebind
    # still hits the id-only route path. The path-params gate must ignore query-string room_id,
    # otherwise the request flips back onto the room-scoped lookup and 404s on thread messages.
    post api_bots_room_message_thread_url(@room, @message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "First reply" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    reply_id = response.parsed_body.dig("message", "id")

    patch api_bots_message_url(id: reply_id, room_id: @room.id), # stale room_id in query
      params: "Updated reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    assert_equal "Updated reply", Message.find(reply_id).plain_text_body
  end

  test "id-only edit resolves into thread rooms without the caller passing the thread room id" do
    # Bot creates a thread off its own message; the first reply lives in a brand-new thread room.
    post api_bots_room_message_thread_url(@room, @message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "First reply" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    reply_id = response.parsed_body.dig("message", "id")

    # PATCH the reply via the id-only route — caller never reads the thread room id.
    patch api_bots_message_url(id: reply_id),
      params: "Updated reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :success
    assert_equal "Updated reply", Message.find(reply_id).plain_text_body
  end
end
