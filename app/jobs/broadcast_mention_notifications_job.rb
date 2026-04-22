class BroadcastMentionNotificationsJob < ApplicationJob
  queue_as :default

  def perform(message_id:)
    Notification.where(message_id: message_id, activity_type: "mention")
                .with_message_and_creator
                .each do |notification|
      Turbo::StreamsChannel.broadcast_append_to(
        [ notification.user, :inbox_activity ],
        target: "inbox",
        partial: "notifications/notification",
        locals: { notification: notification, timestamp_style: :long_datetime }
      )
    end
  end
end
