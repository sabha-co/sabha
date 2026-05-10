# Per-user accumulator for missed-notification email candidates.
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 6.2 and § 7.1.
#
# Tenanted: in SaaS each workspace's tenant DB has its own bundles. A user in
# workspaces A and B can have one active bundle in each — bundles never cross
# tenant boundaries (arch § 9).
#
# Active bundle = (user_id, delivered_at IS NULL, canceled_at IS NULL). The
# partial unique index on user_id WHERE delivered_at IS NULL AND canceled_at
# IS NULL guarantees there is at most one active bundle per user.
class Notification::Bundle < ApplicationRecord
  self.table_name = "notification_bundles"

  FREQUENCY_WINDOWS = { "hourly" => 1.hour, "daily" => 24.hours }.freeze

  belongs_to :user
  has_many   :items, class_name: "Notification::BundleItem", foreign_key: :bundle_id, dependent: :delete_all

  enum :frequency, %w[ hourly daily ].index_by(&:itself), prefix: :frequency

  scope :active,   -> { where(delivered_at: nil, canceled_at: nil) }
  scope :pending,  -> { active }

  # Returns the user's active bundle, creating one if none exists. The race-
  # safe insert relies on the partial unique index — two concurrent Message
  # creates in the same second cannot both insert; the loser raises
  # RecordNotUnique and falls through to a second read.
  #
  # Snapshot semantics: `frequency` and `ends_at` are pinned at creation.
  # Later preference flips don't move an in-flight bundle (arch § 14.2).
  def self.find_or_create_active_for(user)
    if existing = active.find_by(user_id: user.id)
      return existing
    end

    frequency = user.notification_settings&.email_frequency || "hourly"
    starts_at = Time.current
    ends_at   = starts_at + FREQUENCY_WINDOWS.fetch(frequency)

    create!(user: user, frequency: frequency, starts_at: starts_at, ends_at: ends_at)
  rescue ActiveRecord::RecordNotUnique
    active.find_by!(user_id: user.id)
  end

  def active?
    delivered_at.nil? && canceled_at.nil?
  end
end
