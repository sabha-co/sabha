require "test_helper"

class WebPush::PoolTest < ActiveSupport::TestCase
  include WebPushPoolReset, DnsTestHelper

  setup do
    stub_dns_resolution "104.18.0.1"
    @pool = Rails.configuration.x.web_push_pool
    @payload = { title: "Hi", body: "There", path: "/" }
    @subscriptions = Push::Subscription.all.to_a
  end

  # A posted delivery can't be recalled. Building a notification hits the DB for
  # the badge count and resolves the endpoint's DNS, either of which can raise —
  # so if the third of four blows up after two are already posted, the job
  # retries and those two users get the push twice. Build everything, then post.
  test "posts nothing when building a notification raises partway through" do
    @subscriptions.third.stubs(:notification).raises(ActiveRecord::StatementInvalid, "database is locked")

    assert_raises ActiveRecord::StatementInvalid do
      @pool.queue(@payload, @subscriptions)
    end

    assert_equal 0, @pool.delivery_pool.scheduled_task_count,
      "a raise while building must leave nothing posted, so a retry can't duplicate"
  end

  test "posts every delivery once the build succeeds" do
    @pool.queue(@payload, @subscriptions)

    assert_equal @subscriptions.size, @pool.delivery_pool.scheduled_task_count
  end

  # The posting phase runs after every fallible decision, so it must not raise.
  # A full delivery pool is the realistic way it could.
  test "posting does not raise when the delivery pool rejects the task" do
    @pool.delivery_pool.stubs(:post).raises(Concurrent::RejectedExecutionError)

    assert_nothing_raised { @pool.queue(@payload, @subscriptions) }
  end
end
