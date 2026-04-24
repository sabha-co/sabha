class Bots::RoomsController < Bots::BaseController
  before_action :set_room, only: %i[update destroy]
  before_action :require_creator, only: %i[update destroy]

  def index
    rooms = if params[:joinable].present?
      Rooms::Open.browsable_by(Current.user)
    else
      Current.user.rooms.without_threads
    end

    render json: rooms.map { |room|
      room.as_bot_json(url_helper: method(:api_bots_room_messages_url))
    }
  end

  def create
    type = params[:type]&.downcase
    name = params[:name]

    unless name.present?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    unless type.in?(%w[open closed])
      return render json: { error: "Type must be 'open' or 'closed'", code: "validation_failed" }, status: :unprocessable_entity
    end

    room_class = type == "open" ? Rooms::Open : Rooms::Closed
    room = room_class.create_for({ name: name }, users: Current.user)

    render json: room.as_bot_json(url_helper: method(:api_bots_room_messages_url)), status: :created
  end

  def update
    old_name = @room.name
    name = params[:name]

    unless name.present?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    @room.update!(name: name)
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name
    RoomUpdateBroadcastJob.perform_later(@room)

    render json: @room.as_bot_json(url_helper: method(:api_bots_room_messages_url))
  end

  def destroy
    @room.deactivate
    broadcast_remove_room

    head :no_content
  rescue Room::CannotDeleteOriginalError
    render json: { error: "The original room can't be deleted", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def set_room
      @room = Current.user.rooms.find(params[:id])
    end

    def broadcast_remove_room
      Sidebar::SIDEBAR_SECTIONS.each do |list_name|
        broadcast_remove_to Current.account, :rooms, target: [ @room, helpers.dom_prefix(list_name, :list_node) ]
      end
    end
end
