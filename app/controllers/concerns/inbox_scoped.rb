module InboxScoped
  extend ActiveSupport::Concern

  private
    def paginating?
      params[:before].present? || params[:after].present?
    end

    def find_messages_with(query_class, **options)
      query = query_class.new(Current.user, **options)
      Message.with_thread_participants(paginate(query.call.with_bookmark_status_for(Current.user)))
    end

    # Bookmarks paginate by bookmark records but return their messages.
    def find_bookmarked_messages
      bookmarks = paginate Inbox::BookmarksQuery.new(Current.user).call
      Message.with_thread_participants(bookmarks.map(&:message)).each { |m| m.bookmarked = true }
    end

    def find_notifications
      query = Inbox::ActivityQuery.new(Current.user)

      paginate(query.call).tap do |notifications|
        messages = notifications.filter_map(&:message)
        Message.with_thread_participants(messages)
        preload_bookmark_status(messages)
      end
    end

    def paginate(records)
      case
      when params[:before].present?
        records.page_before(@before)
      when params[:after].present?
        records.page_after(@after)
      else
        records.last_page
      end
    end

    def preload_bookmark_status(messages)
      return if messages.empty?

      bookmarked_ids = Bookmark.where(user: Current.user, message_id: messages.map(&:id))
                               .pluck(:message_id).to_set
      messages.each { |m| m.bookmarked = bookmarked_ids.include?(m.id) }
    end

    def set_notification_pagination_anchors
      @before = Notification.find_by(id: params[:before])
      @after = Notification.find_by(id: params[:after])
    end

    def set_message_pagination_anchors
      @before = Message.active.find_by(id: params[:before])
      @after = Message.active.find_by(id: params[:after])
    end

    def set_bookmark_pagination_anchors
      @before = Bookmark.find_by(message_id: params[:before], user_id: Current.user.id) if params[:before].present?
      @after = Bookmark.find_by(message_id: params[:after], user_id: Current.user.id) if params[:after].present?
    end

    def track_last_loaded_notification
      session[:inbox_last_loaded_activity_created_at] = (@notifications.last&.created_at || Time.current).iso8601(6)
    end

    def track_last_loaded_message(key)
      session[key] = (@messages.last&.created_at || Time.current).iso8601(6)
    end
end
