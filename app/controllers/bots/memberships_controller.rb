class Bots::MembershipsController < Bots::BaseController
  def create
    room = Room.active.find(params[:room_id])

    unless room.open?
      return render json: { error: "Can only join open rooms", code: "validation_failed" }, status: :unprocessable_entity
    end

    room.accept_join!(Current.user)

    render json: room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url)), status: :created
  end

  def destroy
    room = Current.user.rooms.find(params[:room_id])

    if room.direct?
      return render json: { error: "Cannot leave direct messages", code: "validation_failed" }, status: :unprocessable_entity
    end

    room.accept_leave!(Current.user)

    head :no_content
  rescue Membership::LastVisibleMemberError
    render json: { error: "You're the last member", code: "validation_failed" }, status: :unprocessable_entity
  end
end
