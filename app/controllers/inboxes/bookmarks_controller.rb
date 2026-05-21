class Inboxes::BookmarksController < InboxesController
  before_action :set_bookmark_pagination_anchors, if: :paginating?

  def index
    @messages = find_bookmarked_messages

    render partial: "items" if paginating?
  end
end
