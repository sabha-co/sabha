class UserUnreadRoomsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "user_#{current_user.id}_unreads"
  end
end
