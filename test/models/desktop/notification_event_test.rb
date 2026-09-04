require "test_helper"

class Desktop::NotificationEventTest < ActiveSupport::TestCase
  test "builds a stable event id from message and user" do
    message = rooms(:designers).messages.create!(
      body: "Stable id",
      creator: users(:david),
      client_message_id: "desktop_event_id"
    )
    user = users(:kevin)

    assert_equal "#{message.id}:#{user.id}", Desktop::NotificationEvent.event_id_for(message: message, user: user)
  end

  test "serializes title body path badge and collapsed activity types" do
    room = rooms(:david_and_kevin)
    message = room.messages.create!(
      body: "Hello there",
      creator: users(:david),
      client_message_id: "desktop_event_payload"
    )
    user = users(:kevin)

    payload = Desktop::NotificationEvent.new(
      message: message,
      user: user,
      activity_types: [ :direct_message, :mention ]
    ).as_json

    assert_equal "notification", payload[:type]
    assert_equal 1, payload[:protocol_major]
    assert_equal [ "direct_message", "mention" ], payload[:activity_types]
    assert_equal users(:david).name, payload[:title]
    assert_equal "Hello there", payload[:body]
    assert_includes payload[:path], room.to_param
    assert_kind_of Integer, payload[:badge]
  end

  test "deliver broadcasts through the desktop channel" do
    room = rooms(:david_and_jason)
    message = room.messages.create!(
      body: "Deliver me",
      creator: users(:david),
      client_message_id: "desktop_event_deliver"
    )
    user = users(:jason)

    DesktopChannel.expects(:broadcast_to_user).with(user, kind_of(Hash)).once

    Desktop::NotificationEvent.deliver_for(
      message: message,
      user: user,
      activity_types: [ :direct_message ]
    )
  end
end
