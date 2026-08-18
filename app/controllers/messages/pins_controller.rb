class Messages::PinsController < ApplicationController
  before_action :set_message
  before_action :ensure_staff
  before_action :ensure_pinnable_room

  def create
    @message.pin!

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to room_url(@message.room) }
    end
  end

  def destroy
    @message.unpin!

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to room_url(@message.room) }
    end
  end

  private
    def set_message
      @message = Current.user.reachable_message(params[:message_id])
    end

    def ensure_staff
      head :forbidden unless Current.user.staff?
    end

    def ensure_pinnable_room
      head :forbidden unless @message.room.pinnable?
    end
end
