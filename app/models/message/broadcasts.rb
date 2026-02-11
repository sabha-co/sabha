module Message::Broadcasts
  extend ActiveSupport::Concern

  def broadcast_create
    broadcast_append_to room, :messages, target: [ room, :messages ], partial: "messages/message", locals: { current_room: room, is_unread: true }
    # User-scoped broadcasts are handled via Membership#broadcast_unread when memberships are marked unread

    broadcast_notifications
    broadcast_to_inbox_activity
    broadcast_to_inbox_threads
    broadcast_to_inbox_direct_messages
  end

  def broadcast_update
    broadcast_replace_to room, :messages, target: [ self, :presentation ], partial: "messages/presentation", locals: { message: self }, attributes: { maintain_scroll: true }
    broadcast_replace_to :inbox, target: [ self, :presentation ], partial: "messages/presentation", locals: { message: self }, attributes: { maintain_scroll: true }

    broadcast_notifications(ignore_if_older_message: true)
  end

  def broadcast_notifications(ignore_if_older_message: false)
    user_ids = notification_recipient_ids(ignore_if_older_message)
    return if user_ids.empty?

    payload = { roomId: room.id }

    # Auto-batching enabled in config/anycable.yml handles aggregation
    User.where(id: user_ids).find_each do |user|
      UnreadNotificationsChannel.broadcast_to(user, payload)
    end
  end

  def notification_recipient_ids(ignore_if_older_message)
    # Early return if no one to notify (non-@everyone with no mentionees)
    return [] if !mentions_everyone? && mentionee_ids.blank?

    scope = if mentions_everyone?
      room.memberships
    else
      room.memberships.where(user_id: mentionee_ids)
    end

    if ignore_if_older_message
      # Filter in SQL: exclude users who have read or whose unread_at is after this message
      scope = scope.where("unread_at IS NOT NULL AND unread_at <= ?", created_at)
    end

    scope.pluck(:user_id)
  end

  def broadcast_reactivation
    previous_message = room.messages.active.order(:created_at).where("created_at < ?", created_at).last
    if previous_message.present?
      target = previous_message
      action = "after"
    else
      target = [ room, :messages ]
      action = "prepend"
    end

    broadcast_action_to room, :messages,
                        action:,
                        target:,
                        partial: "messages/message",
                        locals: { message: self, current_room: room, is_unread: true },
                        attributes: { maintain_scroll: true }
  end

  def broadcast_to_inbox_activity
    return if mentionee_ids.blank?
    return if mentions_everyone?

    mentionees.each do |user|
      next if user.id == creator_id

      broadcast_remove_to user, :inbox_activity,
                         target: ActionView::RecordIdentifier.dom_id(self)

      broadcast_append_to user, :inbox_activity,
                          target: "inbox",
                          partial: "messages/message",
                          locals: {
                            message: self,
                            current_room: nil,
                            first_unread_message: nil,
                            timestamp_style: :long_datetime,
                            show_date_separator: true
                          }
    end
  end

  def broadcast_remove
    broadcast_remove_to room, :messages
    broadcast_remove_to :inbox
  end

  def broadcast_to_inbox_threads
    return unless room.thread? && room.parent_message

    BroadcastInboxThreadsJob.perform_later(
      thread_id: room.id,
      parent_message_id: room.parent_message_id,
      message_id: id,
      creator_id: creator_id
    )
  end

  def broadcast_to_inbox_direct_messages
    return unless room.direct?

    BroadcastInboxDirectMessagesJob.perform_later(room_id: room.id)
  end

  def broadcast_mentionee_sidebar_updates
    mentionees.each do |user|
      memberships = user.memberships.shared.visible
      { starred_rooms: memberships, shared_rooms: memberships }.each do |list_name, scope|
        user.broadcast_replace_to user, :rooms,
          target: list_name,
          partial: "users/sidebars/rooms/shared_rooms_list",
          locals: { list_name:, memberships: scope.with_room_by_last_active_newest_first },
          attributes: { maintain_scroll: true }
      end
    end
  end
end
