# Per-test reset of the shared WebPush::Pool. Tests that drive real deliveries
# through the pool (and assert against `pool.completed_task_count`) need a
# fresh pool each run so counters and queued tasks don't leak across tests.
#
# Moved out of the global ActiveSupport::TestCase setup because the previous
# pool shutdown blocks on `wait_for_termination(1)` per delivery thread,
# costing up to ~2s on every test even though only push-pool tests need it.
module WebPushPoolReset
  extend ActiveSupport::Concern

  included do
    setup do
      Rails.configuration.tap do |config|
        config.x.web_push_pool.shutdown
        config.x.web_push_pool = WebPush::Pool.new \
          invalid_subscription_handler: config.x.web_push_pool.invalid_subscription_handler
      end
    end
  end
end
