class Inboxes::NotificationsController < InboxesController
  before_action :set_message_pagination_anchors

  layout false

  def index
    @messages = find_messages_with(Inbox::MessagesQuery, involvement: :notifications_on)

    render "inboxes/messages/index"
  end
end
