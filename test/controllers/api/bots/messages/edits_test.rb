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
end
