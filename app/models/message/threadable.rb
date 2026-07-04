module Message::Threadable
  extend ActiveSupport::Concern

  included do
    after_create_commit :involve_creator_in_thread
    after_create_commit :follow_post_by_creator
    after_create_commit :update_thread_reply_count
    after_create_commit :update_parent_message_threads
    after_create_commit :update_forum_gallery_card
    after_create_commit :create_thread_reply_notifications
    after_update_commit :broadcast_parent_message_to_threads
  end

  private
    def involve_creator_in_thread
      room.involve_user(creator, unread: false) if room.thread?
    end

    # A reply (or the opening message) makes its author a follower of the post,
    # lazily — forum posts don't fan membership out to every member, so
    # engagement is what creates the row. Mirrors Fizzy's
    # Comment#watch_card_by_creator.
    def follow_post_by_creator
      room.follow!(creator) if room.post?
    end

    def update_thread_reply_count
      return unless room.thread? || room.post?

      # A chat thread's messages are all replies; a post's exclude the OP.
      count = room.post? ? room.replies_count : room.messages_count
      broadcast_update_to(
        room,
        :messages,
        target: "#{ActionView::RecordIdentifier.dom_id(room, :replies_separator)}_count",
        html: ActionController::Base.helpers.pluralize(count, "reply", "replies")
      )
    end

    def update_parent_message_threads
      if room.thread? && room.parent_message
        broadcast_replace_to(
          room.parent_message.room,
          :messages,
          target: ActionView::RecordIdentifier.dom_id(room.parent_message, :threads),
          partial: "messages/threads",
          locals: { message: room.parent_message }
        )
      end
    end

    # A reply in a forum post must refresh the gallery card (reply count, last
    # activity, participant avatars). The chat-oriented broadcast above targets
    # `dom_id(parent_message, :threads)`, which exists in a chat message list but
    # not in the forum gallery — so the post-thread owns the card replace (the
    # same broadcast fires on a title/Solved change).
    def update_forum_gallery_card
      room.broadcast_gallery_card if room.post?
    end

    def create_thread_reply_notifications
      return unless (room.thread? && room.parent_message) || room.post?

      CreateThreadReplyNotificationsJob.perform_later(message_id: id, thread_id: room.id, creator_id: creator_id)
    end

    def broadcast_parent_message_to_threads
      if saved_change_to_attribute?(:active) && threads.any?
        threads.each do |thread|
          broadcast_replace_to(
            thread,
            :messages,
            target: ActionView::RecordIdentifier.dom_id(self),
            partial: "messages/parent_message",
            locals: { message: self, thread: thread }
          )
        end
      end
    end
end
