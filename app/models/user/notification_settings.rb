# Per-user notification preferences. One row per user, built on user creation.
class User::NotificationSettings < ApplicationRecord
  self.table_name = "user_notification_settings"

  belongs_to :user

  enum :mode,            %w[ nothing mentions_and_dms all ].index_by(&:itself), prefix: :mode
  enum :email_frequency, %w[ hourly daily ].index_by(&:itself),                 prefix: :email_frequency

  scope :due_for_weekly_digest, -> {
    where("last_digest_sent_at IS NULL OR last_digest_sent_at < ?", 6.days.ago)
  }

  def unsubscribe_from!(surface)
    case surface.to_sym
    when :missed_notifications then update!(missed_email_enabled: false)
    when :weekly_digest        then update!(weekly_digest_subscribed: false)
    else raise ArgumentError, "unknown unsubscribe surface #{surface.inspect}"
    end
  end
end
