class CreateThreadReplyNotificationsJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  # thread_id is the room a reply lives in — a chat thread or a forum post.
  def perform(message_id:, thread_id:, creator_id:)
    room = Room.find_by(id: thread_id)
    message = Message.find_by(id: message_id)
    return unless room && message

    container = reply_container_for(room)
    return unless container
    return if container.direct?

    # Followers of this thread/post, plus members who opted into "everything" on
    # the container (a chat thread's parent room, or a forum post's forum). Same
    # recipient logic as BroadcastInboxThreadsJob.
    room_user_ids = room.memberships.active.visible.pluck(:user_id)
    container_user_ids = container.memberships.active.involved_in_everything.pluck(:user_id)
    all_user_ids = (room_user_ids + container_user_ids).uniq - [ creator_id ]

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
    Notification.append_and_broadcast(
      Notification.where(message_id: message_id, activity_type: "thread_reply", user_id: recipient_ids)
    )
  end

  private
    # The container whose "everything" members also hear about a reply: a forum
    # post's forum, or a chat thread's parent room — both the sub-room's
    # parent_room.
    def reply_container_for(room)
      room.parent_room if room.sub_room?
    end
end
