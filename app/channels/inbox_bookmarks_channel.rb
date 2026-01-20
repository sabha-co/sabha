class InboxBookmarksChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_bookmarks
  end
end
