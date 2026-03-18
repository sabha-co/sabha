class Rooms::ThreadsController < RoomsController
  skip_before_action :remember_last_room_visited, only: %i[ show create ]
  skip_before_action :ensure_has_real_name, only: %i[ show create ]
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :set_membership, only: %i[ show edit ]
  before_action :set_parent_message, only: %i[ create ]

  def create
    @room = Rooms::Thread.find_or_create_for(@parent_message, users: parent_room.users)
    @room.involve_user(Current.user, unread: false)

    redirect_to rooms_thread_path(@room)
  end

  def show
    @messages = find_messages
    render layout: false
  end

  def edit
    @users = @room.visible_users.active.includes(avatar_attachment: :blob).ordered
  end

  def update
    @room.update! room_params

    redirect_to room_at_message_path(@room.parent_message.room, @room.parent_message)
  end

  def destroy
    deactivate_room
    redirect_to room_at_message_path(@room.parent_message.room, @room.parent_message)
  end

  private
  def set_parent_message
    if message = Current.user.reachable_messages.joins(:room).where.not(room: { type: [ "Rooms::Direct", "Rooms::Thread" ] }).find_by(id: params[:parent_message_id])
      @parent_message = message
    else
      redirect_to root_url, alert: "Message not found or inaccessible"
    end
  end

  def parent_room
    @parent_message.room
  end

  def room_params
    params.require(:room).permit(:name)
  end
end
