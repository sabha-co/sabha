class Rooms::DirectsController < RoomsController
  skip_before_action :set_room, only: %i[ edit destroy ]
  skip_before_action :ensure_can_administer, only: %i[ destroy ]

  before_action :set_direct_room, only: %i[ edit destroy ]
  before_action :ensure_permission_to_create_direct_messages, only: %i[ new create ]

  def new
    @room = Rooms::Direct.new
  end

  def create
    create_room
    redirect_to room_url(@room)
  end

  def edit ; end

  def destroy
    deactivate_room
    redirect_to root_url
  end

  private

    def set_direct_room
      @room = Current.user.rooms.find_by(id: params[:id], type: Rooms::Direct.sti_name)
      redirect_to root_url, alert: "Conversation not found" unless @room
    end

    def create_room
      @room = Rooms::Direct.find_or_create_for(selected_users)
      broadcast_create_room(@room)
    end

    def selected_users
      User.where(id: selected_users_ids.including(Current.user.id))
    end

    def selected_users_ids
      params.fetch(:user_ids, [])
    end

    def broadcast_create_room(room)
      room.memberships.each do |membership|
        membership.broadcast_prepend_to membership.user, :rooms,
          target: :direct_rooms,
          partial: "users/sidebars/rooms/direct"
      end
    end

    def ensure_permission_to_create_direct_messages
      return unless Current.account.settings.restrict_direct_messages_to_administrators?
      head :forbidden unless Current.user.administrator?
    end
end
