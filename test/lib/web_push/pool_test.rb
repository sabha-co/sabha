require "test_helper"

class WebPush::PoolTest < ActiveSupport::TestCase
  include WebPushPoolReset

  setup do
    @pool = Rails.configuration.x.web_push_pool
    @payload = { title: "Hi", body: "There", path: "/" }
  end

  # A posted delivery can't be recalled. Building a notification hits the DB for
  # the badge count and resolves the endpoint's DNS, either of which can raise —
  # so if #3 of 5 blows up after #1 and #2 are already posted, the job retries
  # and those two users get the push twice. Build everything, then post.
  test "posts nothing when building a notification raises partway through" do
    subscriptions = build_subscriptions(5)
    subscriptions[2].stubs(:notification).raises(ActiveRecord::StatementInvalid, "database is locked")

    assert_raises ActiveRecord::StatementInvalid do
      @pool.queue(@payload, subscriptions)
    end

    assert_equal 0, @pool.delivery_pool.scheduled_task_count,
      "a raise while building must leave nothing posted, so the retry doesn't duplicate"
  end

  test "posts every delivery once the build succeeds" do
    @pool.queue(@payload, build_subscriptions(5))

    assert_equal 5, @pool.delivery_pool.scheduled_task_count
  end

  test "builds each notification exactly once per subscription" do
    subscriptions = build_subscriptions(3)
    subscriptions.each { |subscription| subscription.expects(:notification).once.returns(stub(deliver: nil)) }

    @pool.queue(@payload, subscriptions)
  end

  # The posting phase runs after every fallible decision, so it must not raise —
  # a full delivery pool is the realistic way it could, and it's swallowed.
  test "posting does not raise when the delivery pool rejects the task" do
    @pool.delivery_pool.stubs(:post).raises(Concurrent::RejectedExecutionError)

    assert_nothing_raised { @pool.queue(@payload, build_subscriptions(2)) }
  end

  private
    def build_subscriptions(count)
      Array.new(count) do |index|
        stub("subscription-#{index}", id: index + 1, notification: stub(deliver: nil))
      end
    end
end
