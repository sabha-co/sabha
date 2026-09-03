class BroadcastUnreadNotificationsJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError::RecordNotFound

  def perform(message_id:, ignore_if_older_message: false)
    message = Message.find_by(id: message_id)
    return unless message

    user_ids = message.notification_recipient_ids(ignore_if_older_message)
    return if user_ids.empty?

    payload = { roomId: message.room.id }

    # Auto-batching enabled in config/anycable.yml handles aggregation
    User.where(id: user_ids).find_each do |user|
      UnreadNotificationsChannel.broadcast_to(user, payload)
    end
  end
end
