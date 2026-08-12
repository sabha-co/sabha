class Inboxes::BookmarksController < ApplicationController
  include InboxScoped

  before_action :set_bookmark_pagination_anchors, if: :paginating?

  def index
    @bookmarks = find_bookmarks

    render partial: "items" if paginating?
  end
end
