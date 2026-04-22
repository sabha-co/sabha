require "test_helper"

class BroadcastMentionNotificationsJobTest < ActiveJob::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  test "broadcasts a notification to each mentioned user's inbox_activity stream" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "mention_broadcast_job_1"
    )

    assert Notification.exists?(user: @jason, message: message, activity_type: "mention")

    assert_turbo_stream_broadcasts [ @jason, :inbox_activity ], count: 1 do
      BroadcastMentionNotificationsJob.perform_now(message_id: message.id)
    end
  end

  test "does nothing when the message has no mention notifications" do
    message = @room.messages.create!(
      body: "Plain message",
      creator: @david,
      client_message_id: "mention_broadcast_job_2"
    )

    assert_turbo_stream_broadcasts [ @jason, :inbox_activity ], count: 0 do
      BroadcastMentionNotificationsJob.perform_now(message_id: message.id)
    end
  end

  test "does nothing when the message has been deleted" do
    assert_turbo_stream_broadcasts [ @jason, :inbox_activity ], count: 0 do
      BroadcastMentionNotificationsJob.perform_now(message_id: 999_999)
    end
  end
end
