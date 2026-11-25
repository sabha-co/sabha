class API::Bots::ChannelsController < API::Bots::BaseController
  before_action :set_channel, only: %i[update destroy]
  before_action :require_creator, only: %i[update destroy]

  def index
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 100)
    page = [ (params[:page].presence || 1).to_i, 1 ].max

    @channels = base_channels.matching(params[:query]).ordered.offset((page - 1) * per_page).limit(per_page)
  end

  def create
    type = params[:type]&.downcase

    unless type.in?(%w[open closed])
      return render json: { error: "Type must be 'open' or 'closed'", code: "validation_failed" }, status: :unprocessable_entity
    end

    if params[:name].blank?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    channel_class = type == "open" ? Channels::Open : Channels::Closed
    @channel = channel_class.create_for({ name: params[:name] }, users: Current.user)

    render :create, status: :created
  end

  def update
    if params[:name].blank?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    old_name = @channel.name
    @channel.update!(name: params[:name])
    @channel.announce_rename(old_name, actor: Current.user) if @channel.name != old_name
    ChannelUpdateBroadcastJob.perform_later(@channel)

    render :update
  end

  def destroy
    @channel.deactivate
    broadcast_sidebar_channel_removed(Current.account, @channel)

    head :no_content
  rescue Channel::CannotDeleteOriginalError
    render json: { error: "The original channel can't be deleted", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def base_channels
      params[:joinable].present? ? Channels::Open.browsable_by(Current.user) : Current.user.channels.without_threads
    end

    def set_channel
      @channel = reachable_bot_channel(params[:id])
    end
end
