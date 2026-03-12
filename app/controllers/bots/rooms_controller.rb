class Bots::RoomsController < ApplicationController
  allow_bot_access only: :index

  def index
    render json: Current.user.rooms.without_threads.map { |room|
      room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url))
    }
  end
end
