require "test_helper"

class BroadcastMentioneeSidebarUpdatesJobTest < ActiveJob::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  test "broadcasts a single row replace to each mentionee" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "mentionee_sidebar_job_1"
    )

    assert_turbo_stream_broadcasts [ @jason, :rooms ], count: 1 do
      BroadcastMentioneeSidebarUpdatesJob.perform_now(message_id: message.id)
    end
  end

  test "broadcasts to every room member except the creator on @everyone" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div>Hey <action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = @room.messages.create!(
      body: body_html,
      creator: @david,
      client_message_id: "mentionee_sidebar_job_everyone"
    )

    assert message.mentions_everyone?

    assert_turbo_stream_broadcasts [ @jason, :rooms ], count: 1 do
      assert_no_turbo_stream_broadcasts [ @david, :rooms ] do
        BroadcastMentioneeSidebarUpdatesJob.perform_now(message_id: message.id)
      end
    end
  end

  test "does nothing for messages in direct rooms" do
    direct = rooms(:david_and_jason)
    message = direct.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "mentionee_sidebar_job_direct"
    )

    assert_no_turbo_stream_broadcasts [ @jason, :rooms ] do
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
