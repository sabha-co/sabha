require "test_helper"

class Messages::EditsByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "edit own message" do
    patch room_bot_message_edit_url(@room, @bot.bot_key, @message),
      params: "Updated text",
      headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :success
    json = response.parsed_body
    assert_equal @message.id, json["id"]
    assert_equal "Updated text", @message.reload.plain_text_body
  end

  test "cannot edit another user's message" do
    other_message = messages(:fourth) # created by david

    patch room_bot_message_edit_url(@room, @bot.bot_key, other_message),
      params: "Hacked",
      headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :forbidden
  end

  test "returns 404 for room bot is not a member of" do
    patch room_bot_message_edit_url(rooms(:designers), @bot.bot_key, messages(:first)),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    patch room_bot_message_edit_url(@room, "999-invalid", @message),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }

    assert_redirected_to new_session_url
  end
end
