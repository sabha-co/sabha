class WelcomeController < ApplicationController
  def show
    if Current.user.rooms.any?
      # Workspace root is a transit redirect to the landing room — preserve any
      # alert/notice the caller set so it reaches the rendered destination.
      flash.keep
      room = landing_room
      target = room_url(room)
      target = target + "?" + request.query_string if request.query_string.present?
      redirect_to target
    else
      render
    end
  end
end
