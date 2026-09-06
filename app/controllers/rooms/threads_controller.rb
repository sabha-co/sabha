class Rooms::ThreadsController < RoomsController
  include ActiveStorage::SetCurrent, NotifyBots

  skip_before_action :remember_last_room_visited, only: %i[ new show create ]
  skip_before_action :ensure_has_real_name, only: %i[ new show create ]
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :set_membership, only: %i[ show edit ]
  before_action :set_parent_message, only: %i[ new create ]

  def new
    # A provisional panel: no thread exists yet, and opening one writes nothing.
    # The thread is materialized only when the first reply is sent (see #create),
    # so an opened-but-abandoned thread leaves no empty room or membership behind.
    #
    # The reply button lives in the cached message partial, so its "new" link can
    # outlive the threadless state. If a thread now exists, show the real one
    # rather than an empty provisional panel that would hide existing replies.
    if existing = @parent_message.threads.active.find_by(type: "Rooms::Thread")
      redirect_to rooms_thread_path(existing)
    else
      render layout: false
    end
  end

  def create
    # The first reply materializes the thread (Rooms::Thread.reply_to). Opening a
    # thread doesn't subscribe you — you follow lazily on your first reply
    # (Message::Threadable) or via the Follow control. Materializing follows the
    # creator and the parent-message author (find_or_create_for).
    @message = Rooms::Thread.reply_to(@parent_message, creator: Current.user, message_params: message_params)
    @room = @message.room

    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)

    redirect_to rooms_thread_path(@room)
  rescue ActiveRecord::RecordInvalid, Rooms::Thread::BlankReplyError
    # A blank or invalid first reply created nothing (the transaction rolled back
    # the just-opened thread). Re-render the provisional panel so the composer stays.
    render :new, layout: false, status: :unprocessable_entity
  end

  def show
    if turbo_frame_request?
      @messages = find_messages
      render layout: false
    else
      redirect_to room_at_message_path(@room.parent_message.room, @room.parent_message)
    end
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
  def serves?(room)
    room.thread?
  end

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

  def message_params
    params.require(:message).permit(:body, :attachment, :client_message_id)
  end
end
