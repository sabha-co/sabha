class UnreadNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "user_#{current_user.id}_notifications"
  end
end
