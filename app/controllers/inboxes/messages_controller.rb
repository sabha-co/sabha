class Inboxes::MessagesController < InboxesController
  before_action :set_message_pagination_anchors

  layout false

  def index
    @messages = find_messages

    render "inboxes/messages/index"
  end
end
