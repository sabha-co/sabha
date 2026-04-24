class API::Bots::MessagesController < API::Bots::BaseController
  include ActiveStorage::SetCurrent, NotifyBots

  before_action :set_room
  before_action :set_own_message, only: %i[update destroy]

  def index
    messages = @room.messages.active.with_creator.with_attached_attachment.ordered.last(50).reverse
    render json: messages.map { |msg| message_json(msg) }
  end

  def show
    message = @room.messages.active.with_creator.with_attached_attachment.find(params[:id])
    render json: message_json(message)
  end

  def create
    @message = @room.messages.create_with_attachment(message_params)

    if @message.persisted?
      @message.broadcast_create
      @message.broadcast_mentionee_sidebar_updates
      notify_bots(@message, :created)
      head :created, location: room_message_url(@room, @message)
    else
      render json: { error: @message.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
    end
  rescue LoadError
    render json: { error: "Storage service unavailable", code: "service_unavailable" }, status: :service_unavailable
  end

  def update
    body = reading(request.body) { |b| format_mentions(b) }
    @message.update!(body: body)

    @message.broadcast_update
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :updated)

    render json: { id: @message.id, body: { html: @message.body.body.to_s, plain: @message.plain_text_body } }
  end

  def destroy
    @message.deactivate
    @message.broadcast_remove
    notify_bots(@message, :deleted)

    head :no_content
  end

  private
    def set_room
      @room = Current.user.rooms.find(params[:room_id])
    end

    def set_own_message
      @message = @room.messages.active.find(params[:id])
      head :forbidden unless @message.creator_id == Current.user.id
    end

    def message_params
      if params[:attachment]
        params.permit(:attachment)
      else
        reading(request.body) { |body| { body: format_mentions(body) } }
      end
    end

    def format_mentions(body)
      body.to_s.gsub(/@\{(.+?)\}/) do
        user = @room.users.find_by(id: $1)
        user ? mention_user(user) : ""
      end
    end

    def mention_user(user)
      attachment_body = render_to_string partial: "users/mention", locals: { user: user }
      %(<action-text-attachment sgid="#{user.attachable_sgid}" content-type="application/vnd.sabha.mention" content="#{attachment_body.gsub('"', '&quot;')}"></action-text-attachment>)
    end

    def reading(io)
      io.rewind
      yield io.read.force_encoding("UTF-8")
    ensure
      io.rewind
    end

    def message_json(msg)
      { id: msg.id,
        creator: { id: msg.creator.id, name: msg.creator.name },
        body: { html: msg.body.body.to_s, plain: msg.plain_text_body },
        has_attachment: msg.attachment?,
        attachment: msg.attachment? ? attachment_json(msg) : nil,
        mentionees: msg.mentionees.map { |m| { id: m.id, name: m.name } },
        created_at: msg.created_at.iso8601 }
    end

    def attachment_json(message)
      blob = message.attachment.blob
      {
        url: blob.url(expires_in: 1.hour),
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size
      }
    end

    def not_found
      render json: { error: "Room or message not found", code: "not_found" }, status: :not_found
    end
end
