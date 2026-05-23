require "test_helper"

class API::Bots::Messages::CreatesTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "create file" do
    skip "libvips is not available" unless defined?(::Vips)

    post api_bots_room_messages_url(@room), params: {
      attachment: fixture_file_upload("moon.jpg", "image/jpeg")
    }, headers: bot_headers(@bot.bot_key)

    assert_response :created
  end

  # POST with `parent_message_id` — inline thread-reply.

  test "create with parent_message_id creates the message in a new thread room" do
    parent = messages(:fourth) # in watercooler, top-level

    assert_difference -> { Rooms::Thread.count }, 1 do
      post api_bots_room_messages_url(@room, parent_message_id: parent.id),
        params: "Reply in a new thread",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created

    json = response.parsed_body
    assert json["id"].present?
    assert json["room_id"].present?

    thread = Rooms::Thread.find(json["room_id"])
    assert_equal parent, thread.parent_message
    assert_includes thread.users, @bot

    message = Message.find(json["id"])
    assert_equal "Reply in a new thread", message.plain_text_body
    assert_equal thread, message.room

    # Location references the thread room, not the URL room
    assert_match %r{/rooms/#{thread.id}/messages/#{message.id}\b}, response.location
    assert_no_match %r{/rooms/#{@room.id}/messages/#{message.id}\b}, response.location
  end

  test "create with parent_message_id reuses an existing thread room (idempotent)" do
    parent = messages(:fourth)

    post api_bots_room_messages_url(@room, parent_message_id: parent.id),
      params: "First reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    first_room_id = response.parsed_body["room_id"]

    assert_no_difference -> { Rooms::Thread.count } do
      post api_bots_room_messages_url(@room, parent_message_id: parent.id),
        params: "Second reply",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
    assert_equal first_room_id, response.parsed_body["room_id"]
  end

  test "create with parent_message_id pointing at a message in another room returns 404" do
    other_room_message = messages(:first) # in designers, not watercooler

    post api_bots_room_messages_url(@room, parent_message_id: other_room_message.id),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  test "create with parent_message_id pointing at a soft-deleted message returns 404" do
    parent = messages(:fourth)
    parent.deactivate

    post api_bots_room_messages_url(@room, parent_message_id: parent.id),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :not_found
  end

  test "create with parent_message_id pointing at a message already in a thread returns 422" do
    # Reach the nested-thread guard: `@room` (URL room) must itself be a thread room and the
    # parent_message_id must reference a message inside it. That happens only when a bot already
    # has a thread membership and tries to thread again from inside it.
    post api_bots_room_messages_url(@room, parent_message_id: messages(:fourth).id),
      params: "First reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    thread_room_id = response.parsed_body["room_id"]
    nested_parent_id = response.parsed_body["id"]

    post api_bots_room_messages_url(thread_room_id, parent_message_id: nested_parent_id),
      params: "Nope",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end

  test "create with parent_message_id involves the bot in an existing thread it wasn't yet a member of" do
    # Regression: when the thread was created before the bot joined the parent
    # room (or any case where the bot isn't yet a thread member), the inline
    # reply must re-add the bot — otherwise follow-up id-only ops on the reply
    # 404 because Current.user.rooms scopes through active memberships.
    parent = messages(:fourth)
    thread = Rooms::Thread.create_for(
      { parent_message_id: parent.id, creator: users(:david) },
      users: [ users(:david) ]
    )
    refute_includes thread.reload.users, @bot

    post api_bots_room_messages_url(@room, parent_message_id: parent.id),
      params: "Late reply",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :created
    assert_includes thread.reload.users, @bot

    # Follow-up id-only ops on the reply must succeed — proves the membership repair stuck.
    reply_id = response.parsed_body["id"]
    patch api_bots_message_url(reply_id),
      params: "Edited",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    assert_response :success
  end

  test "create with parent_message_id fires the regular-create side effects (broadcast_mentionee_sidebar_updates)" do
    parent = messages(:fourth)

    assert_enqueued_with(job: BroadcastMentioneeSidebarUpdatesJob) do
      post api_bots_room_messages_url(@room, parent_message_id: parent.id),
        params: "Threaded reply",
        headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))
    end

    assert_response :created
  end

  test "create without parent_message_id returns { id, room_id } and Location header" do
    post api_bots_room_messages_url(@room),
      params: "Plain post",
      headers: { "CONTENT_TYPE" => "text/plain" }.merge(bot_headers(@bot.bot_key))

    assert_response :created
    json = response.parsed_body
    assert json["id"].present?
    assert_equal @room.id, json["room_id"]
    assert response.location.present?, "Location header still set so plugins on the no-parent path keep working"
  end
end
