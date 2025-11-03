class RoomChannel < ApplicationCable::Channel
  def subscribed
    if @room = find_room
      stream_for @room
    else
      reject
    end
  end

  private
    def find_room
      current_user.rooms.find_by(id: params[:room_id])
    end
end
