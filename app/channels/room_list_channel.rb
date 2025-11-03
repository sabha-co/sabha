class RoomListChannel < ApplicationCable::Channel
  def subscribed
    stream_from "room_list"
  end
end
