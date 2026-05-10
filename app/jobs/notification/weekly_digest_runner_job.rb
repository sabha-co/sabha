# Untenanted fan-out for the weekly digest. Registered as the recurring task
# in config/recurring.yml — runs at the configured schedule with no tenant.
#
# In SaaS: iterates every workspace tenant via `with_each_tenant`, enqueueing
# Notification::WeeklyDigestJob for each. The gem's ActiveJob integration
# auto-carries the current tenant on the serialized job (gem § Active Job),
# so no explicit tenant arg is needed.
#
# In self-hosted: there is no tenant context — enqueue the digest job once.
#
# See docs/plans/NOTIFICATIONS-IMPLEMENTATION-PLAN.md U8.
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
