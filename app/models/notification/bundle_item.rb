# A single email-routing candidate appended to a Notification::Bundle.
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 6.3.
#
# `kind` vocabulary is intentionally distinct from Notification.activity_type:
# bundle items include "direct_message" (which never produces a Notification
# row in v1); Notification.activity_type does not. Keeping the names different
# prevents the "why is there no Notification with activity_type=direct_message?"
# confusion.
class Notification::BundleItem < ApplicationRecord
  self.table_name = "notification_bundle_items"

  KINDS = %w[ mention direct_message ].freeze

  belongs_to :bundle,  class_name: "Notification::Bundle"
  belongs_to :message
  belongs_to :actor,   class_name: "User"

  validates :kind, inclusion: { in: KINDS }
end
