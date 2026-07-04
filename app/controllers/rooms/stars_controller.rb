class Rooms::StarsController < ApplicationController
  include RoomScoped

  before_action :ensure_starrable

  def create
    @membership.update!(starred: true)

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to room_url(@room) }
    end
  end

  def destroy
    @membership.update!(starred: false)

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to room_url(@room) }
    end
  end

  private

  def ensure_starrable
    head :unprocessable_entity if @room.direct? || @room.thread? || @room.post? || @membership.involved_in_invisible?
  end
end
