class Inboxes::MessagesController < ApplicationController
  include InboxScoped

  before_action :set_message_pagination_anchors, if: :paginating?

  def index
    @messages = find_messages_with(Inbox::MessagesQuery)

    if paginating?
      render partial: "items"
    else
      track_last_loaded_message :inbox_last_loaded_message_created_at
    end
  end
end
