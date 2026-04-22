require "test_helper"

class BroadcastMentioneeSidebarUpdatesJobTest < ActiveJob::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  test "broadcasts starred_rooms and shared_rooms lists to each mentionee" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "mentionee_sidebar_job_1"
    )

    assert_turbo_stream_broadcasts [ @jason, :rooms ], count: 2 do
      BroadcastMentioneeSidebarUpdatesJob.perform_now(message_id: message.id)
    end
  end

  test "does nothing when the message has been deleted" do
    assert_turbo_stream_broadcasts [ @jason, :rooms ], count: 0 do
      BroadcastMentioneeSidebarUpdatesJob.perform_now(message_id: 999_999)
    end
  end

  test "does nothing when the message has no mentionees" do
    message = @room.messages.create!(
      body: "Plain message",
      creator: @david,
      client_message_id: "mentionee_sidebar_job_2"
    )

    assert_turbo_stream_broadcasts [ @jason, :rooms ], count: 0 do
      BroadcastMentioneeSidebarUpdatesJob.perform_now(message_id: message.id)
    end
  end
end
