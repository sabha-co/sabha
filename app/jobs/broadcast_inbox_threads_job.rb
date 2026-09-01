class BroadcastInboxThreadsJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  def perform(thread_id:, parent_message_id:, message_id:, creator_id:)
    thread = Room.find_by(id: thread_id)
    parent_message = Message.find_by(id: parent_message_id)
    return unless thread && parent_message

    all_user_ids = thread.reply_recipient_ids(excluding: creator_id)

    return if all_user_ids.empty?

    # Followers of the thread itself, as opposed to parent-room "everything"
    # members who also hear about the reply. Only a follower gets an unread
    # badge and the Follow control on their inbox card.
    thread_user_ids = thread.memberships.active.visible.pluck(:user_id)

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
        # A brand-new followed thread joins the inbox as a proper card, matching
        # a reload. Its follow control and unread badge are per-viewer (they read
        # Current.user), so render inside the recipient's context — a thread
        # member sees "1 new", a parent-room member who doesn't follow sees none.
        Current.set(user: user) do
          Turbo::StreamsChannel.broadcast_append_to(
            [ user, :inbox_threads ],
            target: "inbox",
            partial: "inboxes/threads/thread_card",
            locals: {
              message: parent_message_with_threads,
              thread: thread,
              unread: thread_user_ids.include?(user_id) ? 1 : 0,
              # A visible thread member is exactly a follower, so the follow
              # control renders without a per-recipient `followed_by?` query.
              followed: thread_user_ids.include?(user_id)
            }
          )
        end
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
