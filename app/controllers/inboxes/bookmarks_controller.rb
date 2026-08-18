class Inboxes::BookmarksController < ApplicationController
  include InboxScoped

  before_action :set_bookmark_pagination_anchors, if: :paginating?

  def index
    @bookmarks = find_bookmarks

    if paginating?
      render partial: "items"
    else
      @bookmarks_count = Inbox::BookmarksQuery.new(Current.user).call.count
    end
  end
end
