require "test_helper"

class Messages::Boosts::ByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "create boost" do
    assert_difference -> { Boost.count }, 1 do
      post api_bots_room_message_boosts_url(@room, @message),
        params: "\u{1f389}",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "\u{1f389}", json["content"]
  end

  test "cannot create duplicate boost" do
    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created

    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :unprocessable_entity
  end

  test "destroy own boost" do
    post api_bots_room_message_boosts_url(@room, @message),
      params: "\u{2764}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    boost_id = response.parsed_body["id"]

    assert_difference -> { Boost.count }, -1 do
      delete api_bots_room_message_boost_url(@room, @message, boost_id), headers: bot_headers(@bot)
    end

    assert_response :no_content
  end

  test "returns 404 for room bot is not a member of" do
    post api_bots_room_message_boosts_url(rooms(:designers), messages(:first)),
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end
end
