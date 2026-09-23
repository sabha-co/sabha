require "test_helper"

class DesktopChannelTest < ActionCable::Channel::TestCase
  tests DesktopChannel

  setup do
    stub_connection(current_user: users(:kevin))
  end

  test "subscribes and sends a badge snapshot without replaying notifications" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream_for users(:kevin)

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

    assert_broadcasts(DesktopChannel.broadcasting_for(users(:jason)), 1) do
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

    badges = capture_broadcasts(DesktopChannel.broadcasting_for(membership.user)) { membership.read }

    assert_equal [ "badge" ], badges.map { |payload| payload["type"] }
    assert_equal membership.user.badge_count, badges.last["count"]
  end

  test "a partial read_until broadcasts a fresh badge" do
    membership = unread_with_notifications(memberships(:david_david_and_jason))
    first, second = 2.times.map { |i| membership.room.messages.create!(body: "Unread #{i}", creator: users(:jason), client_message_id: "badge_read_until_#{i}") }

    badges = capture_broadcasts(DesktopChannel.broadcasting_for(membership.user)) { membership.reload.read_until(first.created_at) }

    assert_equal [ "badge" ], badges.map { it["type"] }
  end

  test "clearing notifications up to a time broadcasts a fresh badge" do
    membership = unread_with_notifications(memberships(:david_david_and_jason))

    badges = capture_broadcasts(DesktopChannel.broadcasting_for(membership.user)) { membership.clear_unread_notifications_until(Time.current) }

    assert_equal [ "badge" ], badges.map { it["type"] }
  end

  test "opening a room with notifications broadcasts a fresh badge" do
    membership = unread_with_notifications(memberships(:david_david_and_jason))

    badges = capture_broadcasts(DesktopChannel.broadcasting_for(membership.user)) { membership.present }

    assert_equal [ 0 ], badges.map { it["count"] }
  end

  test "opening a room with nothing unread broadcasts no badge" do
    membership = memberships(:david_david_and_jason)
    membership.update!(unread_notifications_count: 0)

    assert_no_broadcasts(DesktopChannel.broadcasting_for(membership.user)) { membership.present }
  end

  test "nothing is broadcast while desktop notifications are off" do
    Desktop.stubs(:notifications_enabled?).returns(false)

    assert_no_broadcasts(DesktopChannel.broadcasting_for(users(:kevin))) do
      users(:kevin).broadcast_desktop_badge
    end
  end

  private
    def unread_with_notifications(membership)
      membership.update!(unread_notifications_count: 2, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)
      membership
    end
end
