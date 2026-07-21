require "test_helper"

class Bot::WebhookJobTest < ActiveJob::TestCase
  setup do
    @webhook = webhooks(:betty)
    @room = rooms(:designers)
    DemoMode.stubs(:enabled?).returns(false)
  end

  test "does not retry programming errors" do
    @webhook.stubs(:deliver).raises(NoMethodError, "undefined method `avatar' for nil")

    assert_raises(NoMethodError) do
      Bot::WebhookJob.perform_now(@webhook, "message_created", "{}", @room, false)
    end

    assert_no_enqueued_jobs
  end

  test "retries on HTTP delivery failure (non-2xx response)" do
    @webhook.stubs(:deliver).raises(Webhook::DeliveryError, "Failed to deliver webhook, response: 500 Internal Server Error")

    assert_nothing_raised do
      Bot::WebhookJob.perform_now(@webhook, "message_created", "{}", @room, false)
    end

    assert_enqueued_with(job: Bot::WebhookJob)
  end

  test "skips delivery in DemoMode" do
    DemoMode.stubs(:enabled?).returns(true)
    @webhook.expects(:deliver).never

    Bot::WebhookJob.perform_now(@webhook, "message_created", "{}", @room, false)
  end

  test "discards when the webhook has been deleted" do
    assert_enqueued_with(job: Bot::WebhookJob) do
      Bot::WebhookJob.perform_later(@webhook, "message_created", "{}", @room, false)
    end

    @webhook.destroy!

    # With the record gone, GlobalID deserialization raises
    # ActiveJob::DeserializationError; discard_on must swallow it so the queue
    # closes cleanly instead of surfacing a failed execution nothing can act on.
    assert_nothing_raised do
      perform_enqueued_jobs(only: Bot::WebhookJob)
    end
  end
end
