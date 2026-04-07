class Bots::RoomsController < Bots::BaseController
  before_action :require_bot_authentication
  before_action :set_room, only: %i[update destroy]
  before_action :require_creator, only: %i[update destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    rooms = if params[:joinable].present?
      Rooms::Open.browsable_by(Current.user).map { |room|
        room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url))
      }
    else
      Current.user.rooms.without_threads.map { |room|
        room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url))
      }
    end

    render json: rooms
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

    render json: room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url)), status: :created
  end

  def update
    old_name = @room.name
    name = params[:name]

    unless name.present?
      return render json: { error: "Name is required", code: "validation_failed" }, status: :unprocessable_entity
    end

    @room.update!(name: name)
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name

    render json: @room.as_bot_json(bot_key: Current.user.bot_key, url_helper: method(:room_bot_messages_url))
  end

  def destroy
    @room.deactivate

    head :no_content
  rescue Room::CannotDeleteOriginalError
    render json: { error: "The original room can't be deleted", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def set_room
      @room = Current.user.rooms.find(params[:room_id])
    end

    def require_creator
      head :forbidden unless @room.creator_id == Current.user.id
    end

    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def not_found
      render json: { error: "Room not found", code: "not_found" }, status: :not_found
    end
end
