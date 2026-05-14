class Notification::WeeklyDigestJob < ApplicationJob
  def perform
    Notification::Bundle.gc_terminal!

    return unless Sabha.email_configured?
    return unless Account.sole&.weekly_digest_enabled?

    User.weekly_digest_eligible.find_each do |user|
      user.deliver_weekly_digest_now
    rescue StandardError => error
      # One bad recipient (bounce, provider-side rejection, transient flake)
      # must not block the rest of the workspace's digest. The user is left
      # with last_digest_sent_at unchanged, so next week's run retries them.
      Rails.logger.error("WeeklyDigestJob: skipping user=#{user.id}: #{error.class}: #{error.message}")
    end
  end
end
