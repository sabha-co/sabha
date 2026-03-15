class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Discard jobs targeting a deleted workspace (tenant DB no longer exists)
  discard_on "ActiveRecord::Tenanted::TenantDoesNotExistError" if defined?(ActiveRecord::Tenanted)
end
