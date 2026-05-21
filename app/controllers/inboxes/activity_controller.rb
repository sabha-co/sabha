class Inboxes::ActivityController < ApplicationController
  include InboxScoped

  before_action :set_notification_pagination_anchors, if: :paginating?

  def index
    @notifications = find_notifications

    if paginating?
      render partial: "items"
    else
      track_last_loaded_notification
      Current.user.touch_activity_seen_at
    end
  end
end
