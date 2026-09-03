class BroadcastInboxThreadsJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError::RecordNotFound

  def perform(thread_id:, parent_message_id:, message_id:, creator_id:)
    thread = Room.find_by(id: thread_id)
    parent_message = Message.find_by(id: parent_message_id)
    return unless thread && parent_message

    all_user_ids = thread.reply_recipient_ids(excluding: creator_id)

    return if all_user_ids.empty?

    # Batch load all users at once to avoid N+1 queries
    users_by_id = User.where(id: all_user_ids).index_by(&:id)

    # Preload parent_message with threads only - participant_creators fetches users efficiently
    parent_message_with_threads = Message.includes(:threads).find(parent_message.id)
    Message.with_thread_participants([ parent_message_with_threads ])

    # Check current count at execution time to avoid race conditions when multiple
    # messages are posted quickly.
    is_first_message = thread.messages_count == 1

    all_user_ids.each do |user_id|
      user = users_by_id[user_id]
      next unless user

      if is_first_message
        Turbo::StreamsChannel.broadcast_append_to(
          [ user, :inbox_threads ],
          target: "inbox",
          partial: "messages/message",
          locals: {
            message: parent_message,
            timestamp_style: :long_datetime,
            show_date_separator: true
          }
        )
      else
        Turbo::StreamsChannel.broadcast_replace_to(
          [ user, :inbox_threads ],
          target: ActionView::RecordIdentifier.dom_id(parent_message, :threads),
          partial: "messages/threads",
          locals: { message: parent_message_with_threads }
        )
      end
    end
  end
end
