class Rooms::AccessController < ApplicationController
  include RoomScoped

  before_action :ensure_can_administer

  def update
    room = @room.toggle_access!(open: open_access?)
    RoomUpdateBroadcastJob.perform_later(room)

    notice = open_access? ? "Room is now public" : "Room is now private"
    redirect_to helpers.edit_room_path(room), notice: notice
  end

  private
    def open_access?
      params[:open] == "1"
    end
end
