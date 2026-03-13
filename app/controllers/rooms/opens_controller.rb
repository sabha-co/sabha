class Rooms::OpensController < RoomsController
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :remember_last_room_visited, only: :show
  before_action :force_room_type, only: %i[ edit update ]
  before_action :ensure_permission_to_create_rooms, only: %i[ new create ]

  DEFAULT_ROOM_NAME = "New room"

  def show
    redirect_to room_url(@room)
  end

  def new
    @room = Rooms::Open.new(name: DEFAULT_ROOM_NAME)
  end

  def create
    @room = Rooms::Open.create_for(room_params, users: Current.user)

    broadcast_create_room

    if @room.auto_join?
      redirect_to room_url(@room)
    else
      redirect_to edit_rooms_open_url(@room, tab: "members")
    end
  end

  def edit
    load_users_for_access_management
  end

  def update
    old_name = @room.name

    @room.update! room_params
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name

    RoomUpdateBroadcastJob.perform_later(@room)
    redirect_back fallback_location: room_url(@room), notice: "Changes saved"
  end

  private
    # Allows us to edit a closed room and turn it into an open one on saving.
    def force_room_type
      @room = @room.becomes!(Rooms::Open)
    end

    def broadcast_create_room
      @room.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_room_added(membership.user, @room)
      end
    end
end
