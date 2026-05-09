# Per-user notification preferences. One row per user, built on user creation.
# Schema and defaults match docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 6.1, § 12.
#
# Tenanted: in SaaS each workspace's tenant DB has its own table; a user in
# workspaces A and B has independent settings rows in each (arch § 9).
class User::NotificationSettings < ApplicationRecord
  self.table_name = "user_notification_settings"

  belongs_to :user

  enum :mode,            %w[ nothing mentions_and_dms all ].index_by(&:itself), prefix: :mode
  enum :email_frequency, %w[ hourly daily ].index_by(&:itself),                 prefix: :email_frequency
end
