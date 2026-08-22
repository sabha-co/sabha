class Rooms::ClosedsController < RoomsController
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
    @room = Rooms::Closed.new(name: DEFAULT_ROOM_NAME)
  end

  def create
    room = Rooms::Closed.create_for(room_params, users: [ Current.user ])

    broadcast_create_room(room)
    redirect_to edit_rooms_closed_url(room, tab: "members"), notice: "Room created — add some people to get the conversation going"
  end

  def edit
  end

  def update
    old_name = @room.name

    @room.update! room_params
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name

    RoomUpdateBroadcastJob.perform_later(@room)
    redirect_back fallback_location: room_url(@room), notice: "Changes saved"
  end

  private
    # Open and closed rooms convert into each other, so both are in reach here.
    # Nothing else is: a direct room converted to closed gets a membership list
    # its creator then controls.
    def serves?(room)
      room.convertible?
    end

    # Allows us to edit an open room and turn it into a closed one on saving.
    def force_room_type
      @room = @room.becomes!(Rooms::Closed)
    end

    def broadcast_create_room(room)
      room.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_room_added(membership.user, room)
      end
    end
end
