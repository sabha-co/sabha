class InboxesController < ApplicationController
  before_action :set_notification_pagination_anchors, only: %i[ activity ]
  before_action :set_message_pagination_anchors, only: %i[ notifications messages ]
  before_action :set_bookmark_pagination_anchors, only: %i[ bookmarks ]
  before_action :set_sidebar_memberships, except: :direct_messages
  before_action :set_sidebar_memberships_for_dms, only: :direct_messages

  def show
    clear_last_loaded_message_timestamps

    redirect_to activity_inbox_path
  end

  def activity
    @notifications = find_notifications
    track_last_loaded_notification
  end

  def direct_messages
    session[:inbox_last_loaded_dms_created_at] = Time.current.iso8601
    # @memberships and @direct_room_members already set by set_sidebar_memberships_for_dms
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
      session[:inbox_activity_cleared_at] = session[:inbox_last_loaded_activity_created_at]
      Current.user.mark_activity_as_read(session[:inbox_last_loaded_activity_created_at])
    when "direct_messages"
      Current.user.mark_direct_messages_as_read(session[:inbox_last_loaded_dms_created_at])
    else
      session[:inbox_activity_cleared_at] = session[:inbox_last_loaded_activity_created_at]
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
      Message.with_thread_participants(paginate(query.call.with_bookmark_status_for(Current.user)))
    end

    # Bookmarks require special handling: pagination is on bookmarks, but we return messages
    # All returned messages are bookmarked by definition
    def find_bookmarked_messages
      bookmarks = paginate Inbox::BookmarksQuery.new(Current.user).call
      Message.with_thread_participants(bookmarks.map(&:message)).each { |m| m.bookmarked = true }
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

    def find_notifications
      paginate(Inbox::ActivityQuery.new(Current.user).call).tap do |notifications|
        messages = notifications.filter_map(&:message)
        Message.with_thread_participants(messages)
        preload_bookmark_status(messages)
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

    def track_last_loaded_notification
      session[:inbox_last_loaded_activity_created_at] = (@notifications.last&.created_at || Time.current).iso8601(6)
    end

    def set_message_pagination_anchors
      @before = Message.active.find_by(id: params[:before])
      @after = Message.active.find_by(id: params[:after])
    end

    def set_bookmark_pagination_anchors
      @before = Bookmark.find_by(message_id: params[:before], user_id: Current.user.id) if params[:before].present?
      @after = Bookmark.find_by(message_id: params[:after], user_id: Current.user.id) if params[:after].present?
    end

    def track_last_loaded_message(key)
      session[key] = (@messages.last&.created_at || Time.current).iso8601(6)
    end

    def clear_last_loaded_message_timestamps
      session.delete :inbox_last_loaded_activity_created_at
      session.delete :inbox_last_loaded_notification_created_at
      session.delete :inbox_last_loaded_message_created_at
      session.delete :inbox_activity_cleared_at
    end

    # Sidebar setup for DMs inbox - loads first page for inbox content
    # and the recent/unread list for sidebar.
    def set_sidebar_memberships_for_dms
      sidebar = SidebarMemberships.new(Current.user)

      # Load first page of DMs for inbox content
      @memberships = Inbox::DirectMessagesQuery.new(Current.user).call.last_page
      @direct_memberships = sidebar.direct

      # Load members for both inbox and sidebar lists
      room_ids = (@memberships.map(&:room_id) + @direct_memberships.map(&:room_id)).uniq
      @direct_room_members = Rooms::Direct.members_for_display_by_room(room_ids, excluding: Current.user)
    end
end
