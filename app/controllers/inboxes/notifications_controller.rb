class Inboxes::NotificationsController < InboxesController
  before_action :set_message_pagination_anchors

  def index
    @messages = find_messages_with(Inbox::MessagesQuery, involvement: :notifications_on)

    if paginating?
      render partial: "list"
    else
      track_last_loaded_message :inbox_last_loaded_notification_created_at
    end
  end
end
