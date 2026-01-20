# Fetches the user's bookmarked messages that are still active. Returns Bookmark records for pagination.
class Inbox::BookmarksQuery
  def initialize(user)
    @user = user
  end

  def call
    user.bookmarks
        .joins(:message)
        .includes(message: [ :creator, :threads ])
        .merge(Message.active.with_threads.with_creator)
  end

  private

  attr_reader :user
end
