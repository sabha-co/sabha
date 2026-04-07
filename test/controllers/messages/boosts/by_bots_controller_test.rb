require "test_helper"

class Messages::Boosts::ByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message)
  end

  test "create boost" do
    assert_difference -> { Boost.count }, 1 do
      post room_bot_message_boost_url(@room, @bot.bot_key, @message),
        params: "\u{1f389}",
        headers: { "CONTENT_TYPE" => "text/plain" }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "\u{1f389}", json["content"]
  end

  test "cannot create duplicate boost" do
    post room_bot_message_boost_url(@room, @bot.bot_key, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }
    assert_response :created

    post room_bot_message_boost_url(@room, @bot.bot_key, @message),
      params: "\u{1f44d}",
      headers: { "CONTENT_TYPE" => "text/plain" }
    assert_response :unprocessable_entity
  end

  test "destroy own boost" do
    post room_bot_message_boost_url(@room, @bot.bot_key, @message),
      params: "\u{2764}",
      headers: { "CONTENT_TYPE" => "text/plain" }
    boost_id = response.parsed_body["id"]

    assert_difference -> { Boost.count }, -1 do
      delete room_bot_message_unboost_url(@room, @bot.bot_key, @message, boost_id)
    end

    assert_response :no_content
  end

  test "returns 404 for room bot is not a member of" do
    post room_bot_message_boost_url(rooms(:designers), @bot.bot_key, messages(:first)),
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :not_found
  end
end
