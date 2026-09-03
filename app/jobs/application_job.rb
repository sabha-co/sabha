class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available.
  # Discard only the missing-record case so a transient deserialization failure
  # (e.g. a brief DB outage) still retries rather than silently vanishing.
  # discard_on ActiveJob::DeserializationError::RecordNotFound

  # Discard jobs targeting a deleted workspace (tenant DB no longer exists)
  discard_on "ActiveRecord::Tenanted::TenantDoesNotExistError" if defined?(ActiveRecord::Tenanted)
end
