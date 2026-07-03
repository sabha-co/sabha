module Message::Threadable
  extend ActiveSupport::Concern

  included do
    after_create_commit :involve_creator_in_thread
    after_create_commit :update_thread_reply_count
    after_create_commit :update_parent_message_threads
    after_create_commit :update_forum_gallery_card
    after_create_commit :create_thread_reply_notifications
    after_update_commit :broadcast_parent_message_to_threads
    after_update_commit :deactivate_forum_post_when_opening_message_removed
  end

  private
    def involve_creator_in_thread
      room.involve_user(creator, unread: false) if room.thread?
    end

    def update_thread_reply_count
      if room.thread?
        broadcast_update_to(
          room,
          :messages,
          target: "#{ActionView::RecordIdentifier.dom_id(room, :replies_separator)}_count",
          html: ActionController::Base.helpers.pluralize(room.messages_count, "reply", "replies")
        )
      end
    end

    def update_parent_message_threads
      # Forum posts refresh via update_forum_gallery_card instead — the forum
      # gallery has no `dom_id(parent_message, :threads)` element to target.
      if room.thread? && room.parent_message && !room.forum_post?
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
      room.broadcast_gallery_card if room.thread?
    end

    # A forum post is its opening message plus a Rooms::Thread. Deleting the
    # opening message (the OP body) deletes the post: deactivate the post-thread
    # too, so the post disappears consistently from the gallery, the filters, and
    # its /f/:slug page instead of being orphaned (gone from the gallery but
    # still live at its URL). Runs only on individual message deletes — forum
    # cascade uses update_all, which skips callbacks.
    def deactivate_forum_post_when_opening_message_removed
      return unless saved_change_to_attribute?(:active) && !active?
      return unless room.forum?

      threads.active.find_each(&:deactivate)
    end

    def create_thread_reply_notifications
      return unless room.thread? && room.parent_message

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
