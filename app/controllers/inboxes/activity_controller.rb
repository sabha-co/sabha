class Inboxes::ActivityController < InboxesController
  before_action :set_notification_pagination_anchors

  layout false

  def index
    @notifications = find_notifications

    render "inboxes/activity/index"
  end
end
