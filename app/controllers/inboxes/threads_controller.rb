class Inboxes::ThreadsController < ApplicationController
  include InboxScoped

  before_action :set_message_pagination_anchors, if: :paginating?

  def index
    @messages = find_messages_with(Inbox::ThreadsQuery)

    render partial: "items" if paginating?
  end
end
