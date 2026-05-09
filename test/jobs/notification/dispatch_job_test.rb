require "test_helper"

class Notification::DispatchJobTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:designers)
    @creator = users(:david)
  end

  test "performs notify_recipients on the message" do
    message = @room.messages.create!(
      body: "Dispatch test",
      creator: @creator,
      client_message_id: "dispatch_job_perform"
    )

    Message.any_instance.expects(:notify_recipients).with(only: nil, actor: nil).once

    Notification::DispatchJob.perform_now(message)
  end

  test "passes only: and actor: through to notify_recipients" do
    message = @room.messages.create!(
      body: "Dispatch only test",
      creator: @creator,
      client_message_id: "dispatch_job_only"
    )
    actor = users(:jason)

    Message.any_instance.expects(:notify_recipients).with(only: :boost, actor: actor).once

    Notification::DispatchJob.perform_now(message, only: :boost, actor: actor)
  end

  test "discards the job when the message has been deleted" do
    deleted_id = -1
    serialized_job = Notification::DispatchJob.new
    serialized_job.arguments = [ Message.new(id: deleted_id) ]

    assert_includes Notification::DispatchJob.rescue_handlers.map(&:first),
      "ActiveJob::DeserializationError",
      "DispatchJob must discard on DeserializationError so deleted-message races are tolerated"
  end

  test "skips work in DemoMode" do
    DemoMode.stubs(:enabled?).returns(true)
    message = @room.messages.create!(
      body: "Demo mode skip",
      creator: @creator,
      client_message_id: "dispatch_demo_mode"
    )

    Message.any_instance.expects(:notify_recipients).never

    Notification::DispatchJob.perform_now(message)
  end

  test "boost dispatch via job creates a Notification row matching the inline path" do
    parent = @room.messages.create!(
      body: "Boost target via dispatch",
      creator: @creator,
      client_message_id: "dispatch_boost_target"
    )

    boost = nil
    perform_enqueued_jobs(only: Notification::DispatchJob) do
      boost = parent.boosts.create!(content: "Yes", booster: users(:jason))
    end

    notification = Notification.find_by(message_id: parent.id, activity_type: "boost")
    refute_nil notification
    assert_equal @creator.id, notification.user_id
    assert_equal users(:jason).id, notification.actor_id
    assert_equal boost.id, notification.boost_id
  end

  test "creating a regular message enqueues exactly one DispatchJob (not one per activity_type)" do
    assert_enqueued_jobs 1, only: Notification::DispatchJob do
      @room.messages.create!(
        body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
        creator: @creator,
        client_message_id: "dispatch_one_per_message"
      )
    end
  end
end
