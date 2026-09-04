require "test_helper"

class Desktop::BadgeStateTest < ActiveSupport::TestCase
  test "count matches the push subscription badge aggregate" do
    user = users(:kevin)
    membership = memberships(:kevin_designers)
    membership.update!(unread_notifications_count: 2, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)

    expected = user.memberships.unread.where("unread_notifications_count > 0").count
    assert_equal expected, Desktop::BadgeState.count_for(user)
  end

  test "snapshot exposes protocol major and count" do
    user = users(:david)
    snapshot = Desktop::BadgeState.snapshot_for(user)

    assert_equal "badge", snapshot[:type]
    assert_equal 1, snapshot[:protocol_major]
    assert_equal Desktop::BadgeState.count_for(user), snapshot[:count]
  end

  test "broadcast sends a badge payload to the desktop channel" do
    user = users(:kevin)

    DesktopChannel.expects(:broadcast_to_user).with(user, Desktop::BadgeState.snapshot_for(user)).once

    Desktop::BadgeState.broadcast_to(user)
  end

  test "reading a room emits a badge snapshot" do
    membership = memberships(:david_david_and_jason)
    membership.update!(unread_notifications_count: 2, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)

    Desktop::BadgeState.expects(:broadcast_to).with(membership.user).once

    membership.read
  end
end
