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
      Desktop::NotificationEvent.new(
        message: message,
        user: users(:jason),
        activity_types: [ :direct_message ]
      ).deliver
    end
  end

  test "badge counts the rooms that are unread and notified" do
    memberships(:kevin_designers).update!(unread_notifications_count: 2, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)
    kevin = users(:kevin)

    assert_equal kevin.memberships.unread.where("unread_notifications_count > 0").count, kevin.badge_count
    assert_equal({ type: "badge", protocol_major: 1, count: kevin.badge_count }, DesktopChannel.badge_for(kevin))
  end

  test "reading a room broadcasts a fresh badge" do
    membership = memberships(:david_david_and_jason)
    membership.update!(unread_notifications_count: 2, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)

    badges = capture_broadcasts(DesktopChannel.stream_name_for(membership.user)) { membership.read }

    assert_equal [ "badge" ], badges.map { |payload| payload["type"] }
    assert_equal membership.user.badge_count, badges.last["count"]
  end

  test "nothing is broadcast while desktop notifications are off" do
    Desktop.stubs(:notifications_enabled?).returns(false)

    assert_no_broadcasts(DesktopChannel.stream_name_for(users(:kevin))) do
      users(:kevin).broadcast_desktop_badge
    end
  end
end
