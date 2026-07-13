require "test_helper"

class Message::BroadcastsTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:pets)
    @user = users(:david)
  end

  test "notification_recipient_ids filters to unseen when ignore_if_older_message is true" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = @room.messages.create!(
      body: body_html,
      client_message_id: "test_filter",
      creator: @user
    )

    # One user has seen everything
    catch_up @room.memberships.find_by(user: users(:jason))

    # Another user's cursor sits before this message
    force_all_unread @room.memberships.find_by(user: users(:david))

    user_ids = message.send(:notification_recipient_ids, true)

    # David should be included (message unseen for them)
    assert_includes user_ids, users(:david).id

    # Jason should be excluded (caught up)
    assert_not_includes user_ids, users(:jason).id
  end

  test "broadcast_notifications defers the mention badge push to a job" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      client_message_id: "badge_broadcast_mention",
      creator: @user
    )

    stream_name = UnreadNotificationsChannel.broadcasting_for(users(:jason))

    # Deferred: nothing on the request path, one job enqueued.
    assert_no_broadcasts stream_name do
      assert_enqueued_jobs 1, only: BroadcastUnreadNotificationsJob do
        message.broadcast_notifications
      end
    end

    # The badge push lands when the job runs.
    assert_broadcasts stream_name, 1 do
      perform_enqueued_jobs only: BroadcastUnreadNotificationsJob do
        message.broadcast_notifications
      end
    end
  end

  test "broadcast_notifications does not enqueue a badge push for regular messages" do
    message = @room.messages.create!(
      body: "Plain regular update",
      client_message_id: "badge_broadcast_regular",
      creator: @user
    )

    assert_no_enqueued_jobs only: BroadcastUnreadNotificationsJob do
      message.broadcast_notifications
    end
  end
end
