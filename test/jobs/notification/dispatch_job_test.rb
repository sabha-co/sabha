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
    booster = users(:jason)
    boost = message.boosts.create!(content: "🎉", booster: booster)
    # `boosts.create!` enqueues its own DispatchJob; clear it so we observe
    # only the perform_now call under test.
    clear_enqueued_jobs
    Notification.where(message: message, activity_type: "boost").destroy_all

    Notification::DispatchJob.perform_now(message, only: :boost, actor: booster)

    notification = Notification.find_by(message: message, activity_type: "boost")
    refute_nil notification, "perform_now should drive notify_recipients and create the boost row"
    assert_equal boost.id, notification.boost_id
  end

  test "passes only: and actor: through to notify_recipients" do
    message = @room.messages.create!(
      body: "Dispatch only test",
      creator: @creator,
      client_message_id: "dispatch_job_only"
    )
    actor = users(:jason)
    message.boosts.create!(content: "🔥", booster: actor)
    clear_enqueued_jobs
    Notification.where(message: message, activity_type: "boost").destroy_all

    Notification::DispatchJob.perform_now(message, only: :boost, actor: actor)

    notification = Notification.find_by(message: message, activity_type: "boost")
    refute_nil notification, "only: :boost should run the boost branch"
    assert_equal actor.id, notification.actor_id, "actor: should be forwarded to the dispatch branch"
  end

  test "skips work in DemoMode" do
    DemoMode.stubs(:enabled?).returns(true)
    message = @room.messages.create!(
      body: "Demo mode skip",
      creator: @creator,
      client_message_id: "dispatch_demo_mode"
    )
    booster = users(:jason)
    message.boosts.create!(content: "👍", booster: booster)
    clear_enqueued_jobs
    Notification.where(message: message, activity_type: "boost").destroy_all

    Notification::DispatchJob.perform_now(message, only: :boost, actor: booster)

    assert_nil Notification.find_by(message: message, activity_type: "boost"),
      "DemoMode must short-circuit before any notification side effect"
  end

  test "dispatching the same boost twice creates only one notification" do
    message = @room.messages.create!(
      body: "Dispatch idempotency",
      creator: @creator,
      client_message_id: "dispatch_boost_idempotent"
    )
    booster = users(:jason)
    message.boosts.create!(content: "🎯", booster: booster)
    clear_enqueued_jobs
    Notification.where(message: message, activity_type: "boost").destroy_all

    # A boost notifies its creator exactly once; a duplicate dispatch must find
    # the existing row (via the unique boost_id index) rather than raise or add
    # a second one.
    assert_difference -> { Notification.where(message: message, activity_type: "boost").count }, 1 do
      2.times { Notification::DispatchJob.perform_now(message, only: :boost, actor: booster) }
    end
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
end
