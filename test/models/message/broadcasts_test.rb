require "test_helper"

class Message::BroadcastsTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:pets)
    @user = users(:david)
  end

  test "notification_recipient_ids filters by unread_at when ignore_if_older_message is true" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = @room.messages.create!(
      body: body_html,
      client_message_id: "test_filter",
      creator: @user
    )

    # Mark one user as having read (unread_at = nil)
    @room.memberships.find_by(user: users(:jason)).update!(unread_at: nil)

    # Mark another user as unread before this message
    @room.memberships.find_by(user: users(:david)).update!(unread_at: 1.hour.ago)

    user_ids = message.send(:notification_recipient_ids, true)

    # David should be included (unread_at before message)
    assert_includes user_ids, users(:david).id

    # Jason should be excluded (read - unread_at is nil)
    assert_not_includes user_ids, users(:jason).id
  end

  test "broadcast_notifications broadcasts unread badge updates for mentions" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      client_message_id: "badge_broadcast_mention",
      creator: @user
    )

    stream_name = UnreadNotificationsChannel.broadcasting_for(users(:jason))
    assert_broadcasts stream_name, 1 do
      message.broadcast_notifications
    end
  end

  test "broadcast_notifications does not broadcast unread badge updates for regular messages" do
    message = @room.messages.create!(
      body: "Plain regular update",
      client_message_id: "badge_broadcast_regular",
      creator: @user
    )

    stream_name = UnreadNotificationsChannel.broadcasting_for(users(:jason))
    assert_no_broadcasts stream_name do
      message.broadcast_notifications
    end
  end
end
