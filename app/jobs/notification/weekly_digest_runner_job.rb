# Recurring entry point for the weekly digest. Runs untenanted (the queue DB
# is global) and fans out to one per-tenant job per workspace. Enqueueing
# inside `with_each_tenant` is what carries the tenant onto the serialized
# WeeklyDigestJob — without it the per-tenant job would have no tenant.
class Notification::WeeklyDigestRunnerJob < ApplicationJob
  def perform
    if defined?(ActiveRecord::Tenanted) && Sabha.saas?
      ApplicationRecord.with_each_tenant do
        Notification::WeeklyDigestJob.perform_later
      end
    else
      Notification::WeeklyDigestJob.perform_later
    end
  end
end
