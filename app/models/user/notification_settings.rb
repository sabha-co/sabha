# Per-user notification preferences. One row per user, built on user creation.
class User::NotificationSettings < ApplicationRecord
  self.table_name = "user_notification_settings"

  belongs_to :user

  enum :mode,            %w[ nothing mentions_and_dms all ].index_by(&:itself), prefix: :mode
  enum :email_frequency, %w[ hourly daily ].index_by(&:itself),                 prefix: :email_frequency
end
