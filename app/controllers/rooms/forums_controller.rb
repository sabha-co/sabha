class Rooms::ForumsController < RoomsController
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :remember_last_room_visited, only: :show
  before_action :ensure_permission_to_create_rooms, only: %i[ new create ]

  DEFAULT_FORUM_NAME = "New forum"

  # A forum renders at the canonical /rooms/:id (RoomsController#show draws the
  # gallery), same as open/closed rooms redirect there.
  def show
    redirect_to room_url(@room)
  end

  def new
    @room = Rooms::Forum.new(name: DEFAULT_FORUM_NAME)
  end

  def create
    @room = Rooms::Forum.create_for(forum_params, users: Current.user)

    broadcast_create_room
    redirect_to room_url(@room)
  end

  def edit
    load_users_for_access_management
  end

  def update
    old_name = @room.name

    @room.update! forum_params
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name

    RoomUpdateBroadcastJob.perform_later(@room)
    redirect_back fallback_location: room_url(@room), notice: "Changes saved"
  end

  private
    def serves?(room)
      room.forum?
    end

    def forum_params
      params.require(:room).permit(:name, :description)
    end

    def broadcast_create_room
      @room.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_room_added(membership.user, @room)
      end
    end
end
