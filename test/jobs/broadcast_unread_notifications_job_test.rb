require "test_helper"

class BroadcastUnreadNotificationsJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  test "broadcasts an unread badge nudge to each mentioned user" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "unread_badge_job_1"
    )

    stream = UnreadNotificationsChannel.broadcasting_for(@jason)
    assert_broadcasts stream, 1 do
      BroadcastUnreadNotificationsJob.perform_now(message_id: message.id)
    end
  end

  test "does nothing when the message has been deleted" do
    stream = UnreadNotificationsChannel.broadcasting_for(@jason)
    assert_no_broadcasts stream do
      BroadcastUnreadNotificationsJob.perform_now(message_id: 999_999)
    end
  end

  test "does nothing for a message with no recipients" do
    message = @room.messages.create!(
      body: "Plain message",
      creator: @david,
      client_message_id: "unread_badge_job_2"
    )

    stream = UnreadNotificationsChannel.broadcasting_for(@jason)
    assert_no_broadcasts stream do
      BroadcastUnreadNotificationsJob.perform_now(message_id: message.id)
    end
  end
end
