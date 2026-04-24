class API::Bots::Messages::ThreadsController < API::Bots::BaseController
  def create
    room = Current.user.rooms.find(params[:room_id])
    parent_message = room.messages.active.find(params[:message_id])

    thread = Rooms::Thread.find_or_create_for(parent_message, users: room.users)
    thread.involve_user(Current.user, unread: false)

    message = if params[:attachment]
      thread.messages.create_with_attachment!(attachment: params[:attachment], creator: Current.user)
    else
      body = request.body.tap(&:rewind).read.force_encoding("UTF-8")
      thread.messages.create!(body: body, creator: Current.user)
    end

    message.broadcast_create

    render json: {
      thread: { id: thread.id, parent_message_id: parent_message.id },
      message: { id: message.id }
    }, status: :created
  end
end
