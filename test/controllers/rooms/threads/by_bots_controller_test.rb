require "test_helper"

class Rooms::Threads::ByBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler) # bender has membership here
    @message = messages(:fourth) # in watercooler
  end

  test "creates thread and posts reply" do
    assert_difference -> { Rooms::Thread.count } do
      post api_bots_room_message_thread_url(@room, @message),
        headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "Here is my reply" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    json = response.parsed_body

    assert json["thread"]["id"].present?
    assert_equal @message.id, json["thread"]["parent_message_id"]
    assert json["message"]["id"].present?

    thread = Rooms::Thread.find(json["thread"]["id"])
    assert_equal @message, thread.parent_message
    assert thread.users.include?(@bot)

    reply = Message.find(json["message"]["id"])
    assert_equal "Here is my reply", reply.body.to_plain_text
    assert_equal @bot, reply.creator
  end

  test "reuses existing thread" do
    # Create thread first
    post api_bots_room_message_thread_url(@room, @message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "First reply" }.merge(bot_headers(@bot.bot_key))
    thread_id = response.parsed_body["thread"]["id"]

    assert_no_difference -> { Rooms::Thread.count } do
      post api_bots_room_message_thread_url(@room, @message),
        headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "Second reply" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    assert_equal thread_id, response.parsed_body["thread"]["id"]
  end

  test "returns 404 for message not in room" do
    other_message = messages(:first) # in designers, not watercooler

    post api_bots_room_message_thread_url(@room, other_message),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "Reply" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  test "returns 404 for room bot is not in" do
    room = rooms(:designers) # bender has no membership

    post api_bots_room_message_thread_url(room, messages(:first)),
      headers: { "CONTENT_TYPE" => "text/plain", "RAW_POST_DATA" => "Reply" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end
end
