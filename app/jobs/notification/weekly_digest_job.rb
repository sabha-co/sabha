class Notification::WeeklyDigestJob < ApplicationJob
  def perform
    return if DemoMode.enabled?

    Notification::Bundle.gc_terminal!

    return unless Account.sole&.weekly_digest_enabled?

    User.weekly_digest_eligible.find_each(&:deliver_weekly_digest_now)
  end
end
