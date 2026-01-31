class Inboxes::ActivityController < InboxesController
  before_action :set_message_pagination_anchors

  layout false

  def index
    @messages = find_messages_with(Inbox::ActivityQuery)

    render "inboxes/messages/index"
  end
end
