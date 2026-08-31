class BroadcastMentionNotificationsJob < ApplicationJob
  queue_as :default

  def perform(message_id:)
    Notification.append_and_broadcast(
      Notification.where(message_id: message_id, activity_type: "mention")
    )
  end
end
