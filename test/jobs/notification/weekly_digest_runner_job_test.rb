require "test_helper"

class Notification::WeeklyDigestRunnerJobTest < ActiveSupport::TestCase
  test "self-hosted: enqueues a single WeeklyDigestJob" do
    skip "SaaS-only test path" if Sabha.saas?

    assert_enqueued_with(job: Notification::WeeklyDigestJob) do
      Notification::WeeklyDigestRunnerJob.perform_now
    end
  end
end
