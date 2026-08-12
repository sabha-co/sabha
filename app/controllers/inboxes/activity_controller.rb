class Inboxes::ActivityController < ApplicationController
  include InboxScoped

  before_action :set_notification_pagination_anchors, if: :paginating?

  def index
    @notifications = find_notifications(filter: params[:filter])
    # The pre-touch watermark: rows and the header count mark what arrived
    # since the previous visit, then the visit below advances the mark.
    @activity_last_seen_at = Current.user.activity_seen_at

    if paginating?
      render partial: "items"
    else
      @unread_activity_count = Current.user.unseen_notifications.count
      track_last_loaded_notification
      Current.user.touch_activity_seen_at
    end
  end
end
