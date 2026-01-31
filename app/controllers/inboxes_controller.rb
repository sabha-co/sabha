class InboxesController < ApplicationController
  before_action :set_message_pagination_anchors, only: %i[ activity notifications messages ]
  before_action :set_bookmark_pagination_anchors, only: %i[ bookmarks ]
  before_action :set_sidebar_memberships

  def show
    clear_last_loaded_message_timestamps

    redirect_to activity_inbox_path
  end

  def activity
    @messages = find_messages_with(Inbox::ActivityQuery)

    track_last_loaded_message :inbox_last_loaded_activity_created_at
  end

  def threads
    @messages = find_messages_with(Inbox::ThreadsQuery)
  end

  def notifications
    @messages = find_messages_with(Inbox::MessagesQuery, involvement: :notifications_on)

    track_last_loaded_message :inbox_last_loaded_notification_created_at
  end

  def messages
    @messages = find_messages_with(Inbox::MessagesQuery)

    track_last_loaded_message :inbox_last_loaded_message_created_at
  end

  def bookmarks
    @messages = find_bookmarked_messages
  end

  def clear
    case params[:scope]
    when "activity"
      Current.user.mark_activity_as_read(session[:inbox_last_loaded_activity_created_at])
    else
      Current.user.mark_inbox_as_read(
        messages_loaded_at: session[:inbox_last_loaded_message_created_at],
        notifications_loaded_at: session[:inbox_last_loaded_notification_created_at],
        activity_loaded_at: session[:inbox_last_loaded_activity_created_at]
      )
    end

    redirect_back(fallback_location: activity_inbox_path) unless params[:stay]
  end

  private

    # Unified method for fetching paginated messages from any query object
    def find_messages_with(query_class, **options)
      query = query_class.new(Current.user, **options)
      paginate(query.call.with_bookmark_status_for(Current.user))
    end

    # Bookmarks require special handling: pagination is on bookmarks, but we return messages
    # All returned messages are bookmarked by definition
    def find_bookmarked_messages
      bookmarks = paginate Inbox::BookmarksQuery.new(Current.user).call
      bookmarks.map(&:message).each { |m| m.bookmarked = true }
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

    def set_message_pagination_anchors
      @before = Message.active.find_by(id: params[:before])
      @after = Message.active.find_by(id: params[:after])
    end

    def set_bookmark_pagination_anchors
      @before = Bookmark.active.find_by(message_id: params[:before], user_id: Current.user.id) if params[:before].present?
      @after = Bookmark.active.find_by(message_id: params[:after], user_id: Current.user.id) if params[:after].present?
    end

    def track_last_loaded_message(key)
      session[key] = (@messages.last&.created_at || Time.current).iso8601(6)
    end

    def clear_last_loaded_message_timestamps
      session.delete :inbox_last_loaded_activity_created_at
      session.delete :inbox_last_loaded_notification_created_at
      session.delete :inbox_last_loaded_message_created_at
    end
end
