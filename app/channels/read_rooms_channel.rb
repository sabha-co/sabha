class ReadRoomsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "user_#{current_user.id}_reads"
  end
end
