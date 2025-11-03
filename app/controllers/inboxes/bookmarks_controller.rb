class Inboxes::BookmarksController < InboxesController
  before_action :set_bookmark_pagination_anchors

  layout false

  def index
    @messages = find_bookmarked_messages

    render "inboxes/messages/index"
  end
end
