# Routing vocabulary for the notification dispatcher. Read at routing time only —
# does not all map 1:1 to persisted Notification.activity_type values. The persisted
# enum stays %w[mention boost thread_reply]; :direct_message and :everyone_room_message
# are dispatcher-only.
#
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 3.
module Notification::Routing
  ACTIVITY_TYPES   = %i[mention direct_message everyone_room_message thread_reply boost].freeze
  IN_APP_ROW_TYPES = %i[mention thread_reply boost].freeze
  PUSH_TYPES       = %i[mention direct_message everyone_room_message thread_reply].freeze
  EMAIL_TYPES      = %i[mention direct_message].freeze
end
