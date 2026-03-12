class Bots::RoomsController < ApplicationController
  allow_bot_access only: :index

  def index
    rooms = Current.user.rooms.where.not(type: "Rooms::Thread")
    render json: rooms.map { |room|
      { id: room.id, name: room.name, type: room.type.demodulize,
        messages_url: room_bot_messages_url(room, Current.user.bot_key) }
    }
  end
end
