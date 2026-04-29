require "test_helper"

class API::Bots::MessagesById::BoostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    @message = messages(:bender_message) # bender's own message; ownership check doesn't apply to boosts
    @other_message = messages(:fourth)   # creator: jz, room: watercooler
  end

  test "POST creates a boost on any message the bot can see (no ownership check)" do
    assert_difference -> { Boost.count }, 1 do
      post api_bots_message_boosts_url(@other_message),
        params: "\u{1f389}",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "\u{1f389}", json["content"]
  end

  test "POST returns 404 with canonical envelope for a message in a room the bot can't access" do
    other_message = messages(:first) # in designers; bender has no membership

    post api_bots_message_boosts_url(other_message),
      params: "\u{1f389}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end

  test "DELETE removes the bot's own boost" do
    post api_bots_message_boosts_url(@message),
      params: "\u{2764}",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    boost_id = response.parsed_body["id"]

    assert_difference -> { Boost.count }, -1 do
      delete api_bots_message_boost_url(@message, boost_id), headers: bot_headers(@bot.bot_key)
    end

    assert_response :no_content
  end

  test "DELETE returns 404 with canonical envelope for someone else's boost" do
    other_boost = @message.boosts.create!(content: "\u{1f44d}", booster: users(:jason))

    delete api_bots_message_boost_url(@message, other_boost), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
    assert_equal({ "error" => "Not found", "code" => "not_found" }, response.parsed_body)
  end
end
