# Per-user accumulator for missed-notification email candidates. The partial
# unique index on user_id WHERE delivered_at IS NULL AND canceled_at IS NULL
# guarantees at most one active bundle per user.
class Notification::Bundle < ApplicationRecord
  self.table_name = "notification_bundles"

  FREQUENCY_WINDOWS = { "hourly" => 1.hour, "daily" => 24.hours }.freeze

  belongs_to :user
  has_many   :items, class_name: "Notification::BundleItem", foreign_key: :bundle_id, dependent: :delete_all

  enum :frequency, %w[ hourly daily ].index_by(&:itself)

  scope :active,   -> { where(delivered_at: nil, canceled_at: nil) }
  scope :terminal, -> { where("delivered_at IS NOT NULL OR canceled_at IS NOT NULL") }

  # Active bundles are never pruned — the partial unique index keeps that set
  # bounded to one per user. Only delivered/canceled bundles age out.
  GC_RETENTION = 90.days

  def self.gc_terminal!(retention: GC_RETENTION)
    # delete_all skips dependent: :delete_all, so children would orphan and FK
    # would fire. Pluck → delete items → delete bundles keeps it one round trip
    # per table without instantiation cost.
    ids = terminal.where("updated_at < ?", retention.ago).pluck(:id)
    return if ids.empty?

    Notification::BundleItem.where(bundle_id: ids).delete_all
    Notification::Bundle.where(id: ids).delete_all
  end

  def active?
    delivered_at.nil? && canceled_at.nil?
  end

  def terminal?
    delivered_at.present? || canceled_at.present?
  end

  def cancel!(time = Time.current)
    update!(canceled_at: time)
  end

  def mark_delivered!(time = Time.current)
    update!(delivered_at: time)
  end

  # Called once at bundle creation. Per-item adds do not re-schedule;
  # BundleDeliveryJob skips bundles that are already terminal.
  def schedule_delivery
    Notification::BundleDeliveryJob.set(wait_until: ends_at).perform_later(self)
  end
end
