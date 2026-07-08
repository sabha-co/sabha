class Rooms::ThreadsController < RoomsController
  skip_before_action :remember_last_room_visited, only: %i[ show create ]
  skip_before_action :ensure_has_real_name, only: %i[ show create ]
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :set_membership, only: %i[ show edit ]
  before_action :set_parent_message, only: %i[ create ]

  def create
    # Opening a thread doesn't subscribe you — access derives from the parent room,
    # and you follow lazily on your first reply (Message::Threadable) or explicitly
    # via the Follow control. Creating a *new* thread still follows its creator and
    # the parent-message author, granted by find_or_create_for. Re-subscribing here
    # would undo an Unfollow the next time you opened the thread.
    @room = Rooms::Thread.find_or_create_for(@parent_message, creator: Current.user)

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
    if message = Current.user.reachable_messages.joins(:room).where.not(room: { type: [ "Rooms::Direct", "Rooms::Thread", "Rooms::Forum", "Rooms::Post" ] }).find_by(id: params[:parent_message_id])
      @parent_message = message
    else
      redirect_to root_url, alert: "Message not found or inaccessible"
    end
  end

  def room_params
    params.require(:room).permit(:name)
  end
end
