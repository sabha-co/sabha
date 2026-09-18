require "test_helper"

class DesktopChannelTest < ActionCable::Channel::TestCase
  tests DesktopChannel

  setup do
    stub_connection(current_user: users(:kevin))
  end

  test "subscribes and sends a badge snapshot without replaying notifications" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream "desktop:#{users(:kevin).id}"

    badge = transmissions.last
    assert_equal "badge", badge["type"]
    assert_equal 1, badge["protocol_major"]
    assert_kind_of Integer, badge["count"]
    assert_nil transmissions.find { |payload| payload["type"] == "notification" }
  end

  test "rejects subscription without a user" do
    stub_connection(current_user: nil)

    subscribe

    assert subscription.rejected?
  end

  test "broadcasts a desktop notification event to the subscribed user" do
    room = rooms(:david_and_jason)
    message = room.messages.create!(
      body: "Desktop cable event",
      creator: users(:david),
      client_message_id: "desktop_channel_event"
    )

    assert_broadcasts("desktop:#{users(:jason).id}", 1) do
      Desktop::NotificationEvent.deliver_for(
        message: message,
        user: users(:jason),
        activity_types: [ :direct_message ]
      )
    end
  end
end
