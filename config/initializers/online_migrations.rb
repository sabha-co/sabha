# frozen_string_literal: true

return unless defined?(OnlineMigrations) && Sabha.saas?

OnlineMigrations.configure do |config|
  # Only check migrations created after this date (existing migrations are already deployed).
  config.start_after = { untenanted: 20260413000000 }

  # Match production PostgreSQL version.
  config.target_version = 17

  config.statement_timeout = 1.hour
  config.lock_timeout_limit = 10.seconds
  config.check_down = false
  config.auto_analyze = true

  config.lock_retrier = OnlineMigrations::ExponentialLockRetrier.new(
    attempts: 30,
    base_delay: 0.01.seconds,
    max_delay: 1.minute,
    lock_timeout: 0.2.seconds
  )
end
