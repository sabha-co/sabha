class Rooms::AccessController < ApplicationController
  include RoomScoped

  before_action :ensure_can_administer
  before_action :ensure_room_is_convertible

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

    # Only open and closed rooms carry this toggle, and the members panel only
    # draws it for them. Anything else arriving here — a direct room, a forum, a
    # thread — is an attempt to republish it, not a switch someone was shown.
    def ensure_room_is_convertible
      head :forbidden unless @room.convertible?
    end
end
