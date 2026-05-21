# Fetches the user's bookmarked messages that are still active. Returns Bookmark records for pagination.
class Inbox::BookmarksQuery
  def initialize(user)
    @user = user
  end

  def call
    user.bookmarks
        .joins(:message)
        .includes(message: [
          :room,
          :rich_text_body,
          :threads,
          { creator: [ :badge, { avatar_attachment: { blob: :variant_records } } ] },
          { boosts: { booster: { avatar_attachment: { blob: :variant_records } } } },
          { attachment_attachment: { blob: :variant_records } }
        ])
        .merge(Message.active)
  end

  private

  attr_reader :user
end
