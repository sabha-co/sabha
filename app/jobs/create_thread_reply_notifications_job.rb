class CreateThreadReplyNotificationsJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  def perform(message_id:, thread_id:, creator_id:)
    thread = Room.find_by(id: thread_id)
    message = Message.find_by(id: message_id)
    return unless thread && message && thread.parent_message
    return if thread.parent_message.room.direct?

    # Same recipient logic as BroadcastInboxThreadsJob
    thread_user_ids = thread.memberships.active.visible.pluck(:user_id)
    parent_room_user_ids = thread.parent_message.room.memberships.active.involved_in_everything.pluck(:user_id)
    all_user_ids = (thread_user_ids + parent_room_user_ids).uniq - [ creator_id ]

    return if all_user_ids.empty?

    # Skip users who already got a mention notification for this message
    already_mentioned_user_ids = Notification.where(
      message_id: message_id, activity_type: "mention"
    ).pluck(:user_id).to_set

    recipient_ids = all_user_ids.reject { |uid| already_mentioned_user_ids.include?(uid) }
    return if recipient_ids.empty?

    now = Time.current
    Notification.insert_all(
      recipient_ids.map { |uid|
        { user_id: uid, message_id: message_id, actor_id: creator_id, activity_type: "thread_reply", created_at: now, updated_at: now }
      },
      unique_by: "index_notifications_on_message_user_type"
    )

    # Broadcast to each recipient's activity stream
    Notification.where(message_id: message_id, activity_type: "thread_reply", user_id: recipient_ids)
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
