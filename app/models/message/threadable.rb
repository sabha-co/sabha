module Message::Threadable
  extend ActiveSupport::Concern

  included do
    after_create_commit :involve_creator_in_thread
    after_create_commit :follow_post_by_creator
    after_create_commit :update_thread_reply_count
    after_create_commit :update_parent_message_threads
    after_create_commit :update_forum_gallery_card
    after_create_commit :mark_forum_unread
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
      return unless room.sub_room?

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
          room.parent_room,
          :messages,
          target: ActionView::RecordIdentifier.dom_id(room.parent_message, :threads),
          partial: "messages/threads",
          locals: { message: room.parent_message }
        )
      end
    end

    # A reply bumps the post's activity, so move its gallery card to the top —
    # the right slot under the default "recent" sort — while refreshing its reply
    # count, timestamp, and participant avatars. (A title/Solved change instead
    # keeps the card in place via broadcast_gallery_card, since neither reorders.)
    def update_forum_gallery_card
      room.broadcast_gallery_card_to_top if room.post?
    end

    # A post's activity pokes the forum's sidebar unread for the members who should
    # see it — a new post reaches every member, a mention reaches the people named,
    # a plain reply reaches no one (its followers get an Activity notification). The
    # forum owns no messages, so this is how the signal reaches its sidebar entry;
    # opening the forum clears it via presence (Membership::Connectable.connect).
    def mark_forum_unread
      room.parent_room.mark_unread_from_post(self) if room.post?
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
