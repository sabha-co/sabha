class API::Bots::MembershipsController < API::Bots::BaseController
  def create
    @channel = Channel.active.find(params[:channel_id])

    unless @channel.open?
      return render json: { error: "Can only join open channels", code: "validation_failed" }, status: :unprocessable_entity
    end

    @channel.accept_join!(Current.user)

    render "api/bots/channels/create", status: :created
  end

  def destroy
    channel = reachable_bot_channel(params[:channel_id])

    if channel.direct?
      return render json: { error: "Cannot leave direct messages", code: "validation_failed" }, status: :unprocessable_entity
    end

    channel.accept_leave!(Current.user)

    head :no_content
  rescue Membership::LastVisibleMemberError
    render json: { error: "You're the last member", code: "validation_failed" }, status: :unprocessable_entity
  end
end
