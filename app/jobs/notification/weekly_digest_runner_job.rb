# Recurring entry point for the weekly digest. Runs untenanted (the queue DB
# is global) and fans out to one per-tenant job per workspace. Enqueueing
# inside `with_each_tenant` is what carries the tenant onto the serialized
# WeeklyDigestJob — without it the per-tenant job would have no tenant.
class Notification::WeeklyDigestRunnerJob < ApplicationJob
  def perform
    if defined?(ActiveRecord::Tenanted) && Sabha.saas?
      ApplicationRecord.with_each_tenant do |tenant|
        # Per-tenant rescue: with_each_tenant uses Array#each, so any raise
        # halts the fan-out and silently skips every workspace after this one.
        # The per-user rescue inside WeeklyDigestJob doesn't protect against
        # enqueue-time failures (locked tenant DB, TenantDoesNotExistError on
        # a workspace destroyed mid-iteration, queue DB blip).
        Notification::WeeklyDigestJob.perform_later
      rescue StandardError => error
        Rails.logger.error("WeeklyDigestRunnerJob: tenant=#{tenant} failed to enqueue: #{error.class}: #{error.message}")
      end
    else
      Notification::WeeklyDigestJob.perform_later
    end
  end
end
