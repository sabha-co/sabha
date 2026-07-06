class API::Bots::RoomsController < API::Bots::BaseController
  before_action :set_room, only: %i[update destroy]
  before_action :require_creator, only: %i[update destroy]

  def index
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 100)
    page = [ (params[:page].presence || 1).to_i, 1 ].max

    @rooms = base_rooms.matching(params[:query]).ordered.offset((page - 1) * per_page).limit(per_page)
  end

  def create
    type = params[:type]&.downcase

    unless type.in?(%w[open closed])
      return render json: { error: "Type must be 'open' or 'closed'", code: "validation_failed" }, status: :unprocessable_entity
    end

    if params[:name].blank?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    room_class = type == "open" ? Rooms::Open : Rooms::Closed
    @room = room_class.create_for({ name: params[:name] }, users: Current.user)

    render :create, status: :created
  end

  def update
    if params[:name].blank?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    old_name = @room.name
    @room.update!(name: params[:name])
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name
    RoomUpdateBroadcastJob.perform_later(@room)

    render :update
  end

  def destroy
    @room.deactivate
    broadcast_sidebar_room_removed(Current.account, @room)

    head :no_content
  rescue Room::CannotDeleteOriginalError
    render json: { error: "The original room can't be deleted", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def base_rooms
      params[:joinable].present? ? Rooms::Open.browsable_by(Current.user) : Current.user.rooms.without_threads
    end

    def set_room
      @room = reachable_bot_room(params[:id])
    end
end
