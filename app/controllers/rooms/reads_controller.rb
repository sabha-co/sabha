class Rooms::ReadsController < ApplicationController
  include RoomScoped

  def create
    @membership.read

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to room_url(@room) }
    end
  end
end
