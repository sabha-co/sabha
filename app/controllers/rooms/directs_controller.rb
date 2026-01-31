class Rooms::DirectsController < RoomsController
  skip_before_action :set_room, only: %i[ edit destroy ]
  skip_before_action :ensure_can_administer, only: %i[ destroy ]

  before_action :set_direct_room, only: %i[ edit destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_permission_to_create_direct_messages, only: %i[ new create ]

  def new
    @room = Rooms::Direct.new
  end

  def create
    @room = Rooms::Direct.find_or_create_for(selected_users)

    if @room.persisted?
      redirect_to room_url(@room)
    else
      redirect_to new_rooms_direct_path, alert: "Could not create conversation"
    end
  end

  def edit
    @users = @room.users.many? ? @room.users.without(Current.user) : @room.users
  end

  def destroy
    deactivate_room
    redirect_to root_url
  end

  private
    def set_direct_room
      @room = Current.user.rooms.find_by(id: params[:id], type: Rooms::Direct.sti_name)
      redirect_to root_url, alert: "Conversation not found" unless @room
    end

    def set_membership
      @membership = Current.user.memberships.find_by(room: @room)
    end

    def selected_users
      User.where(id: selected_users_ids.including(Current.user.id))
    end

    def selected_users_ids
      params.fetch(:user_ids, [])
    end

    def ensure_permission_to_create_direct_messages
      head :forbidden unless Current.user.can_create_direct_messages?
    end
end
