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

# online_migrations is a Postgres-only gem. Sabha's SaaS build has two databases:
# the untenanted Postgres store (where the gem belongs) and tenanted SQLite
# per-workspace stores (where it emphatically doesn't). Without these guards the
# gem's Migrator#ddl_transaction calls `with_lock_retries` (PG-only schema
# statement) and its CommandChecker#check_database_version raises "SQLite is not
# supported" — every tenanted migration crashes. Restrict both hooks to
# PostgreSQL connections.
OnlineMigrations::Migrator.module_eval do
  def ddl_transaction(migration_or_proxy)
    migration =
      if migration_or_proxy.is_a?(ActiveRecord::MigrationProxy)
        migration_or_proxy.send(:migration)
      else
        migration_or_proxy
      end

    if use_transaction?(migration) && migration.connection.respond_to?(:with_lock_retries)
      migration.connection.with_lock_retries { super }
    else
      super
    end
  end
end

OnlineMigrations::CommandChecker.class_eval do
  alias_method :_sabha_original_check, :check

  def check(command, *args, &block)
    return true unless @migration.connection.adapter_name.match?(/postg/i)
    _sabha_original_check(command, *args, &block)
  end
  ruby2_keywords(:check) if respond_to?(:ruby2_keywords, true)
end
