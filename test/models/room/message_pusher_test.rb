require "test_helper"

class Room::MessagePusherTest < ActiveSupport::TestCase
  test "build_payload for shared rooms uses room display_name as title and creator-prefixed body" do
    message = rooms(:designers).messages.create!(
      body: "Shared room update",
      creator: users(:david),
      client_message_id: "pusher_shared_payload"
    )

    payload = Room::MessagePusher.payload_for(room: message.room, message: message)

    assert_equal rooms(:designers).display_name, payload[:title]
    assert_equal "David: Shared room update", payload[:body]
    assert_equal Rails.application.routes.url_helpers.room_path(rooms(:designers)), payload[:path]
  end

  test "build_payload for direct rooms uses sender name as title and unprefixed body" do
    message = rooms(:david_and_jason).messages.create!(
      body: "Direct payload",
      creator: users(:jason),
      client_message_id: "pusher_direct_payload"
    )

    payload = Room::MessagePusher.payload_for(room: message.room, message: message)

    assert_equal "Jason", payload[:title]
    assert_equal "Direct payload", payload[:body]
    assert_equal Rails.application.routes.url_helpers.room_path(rooms(:david_and_jason)), payload[:path]
  end

  test "build_payload for thread replies points back to the parent message" do
    parent = rooms(:pets).messages.create!(
      body: "Pusher thread parent",
      creator: users(:david),
      client_message_id: "pusher_thread_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])
    reply = thread.messages.create!(
      body: "Pusher thread reply",
      creator: users(:jason),
      client_message_id: "pusher_thread_reply"
    )

    payload = Room::MessagePusher.payload_for(room: thread, message: reply)

    expected_path = Rails.application.routes.url_helpers.room_at_message_path(parent.room, parent)
    assert_equal expected_path, payload[:path]
  end

  test "MessagePusher does not expose routing methods anymore" do
    refute Room::MessagePusher.method_defined?(:push),
      "Routing belongs on Message; MessagePusher should be payload-only"
    refute Room::MessagePusher.private_method_defined?(:push_to_users_involved_in_everything),
      "Recipient resolution moved to Message#push_recipient_user_ids_for"
    refute Room::MessagePusher.private_method_defined?(:push_to_users_involved_in_mentions),
      "Recipient resolution moved to Message#push_recipient_user_ids_for"
  end
end
