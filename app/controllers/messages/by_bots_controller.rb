class Messages::ByBotsController < MessagesController
  skip_forgery_protection
  skip_before_action :deny_bots
  skip_before_action :set_room, only: %i[update destroy]
  skip_before_action :set_room_if_found, only: %i[update]
  skip_before_action :set_message, only: %i[update destroy]
  skip_before_action :ensure_can_administer, only: %i[update destroy]

  before_action :require_bot_authentication
  before_action :set_own_message, only: %i[update destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def create
    super
    head :created, location: message_url(@message) if @message&.persisted? && !performed?
  rescue LoadError
    render json: { error: "Storage service unavailable", code: "service_unavailable" }, status: :service_unavailable
  end

  def update
    body = reading(request.body) { |b| format_mentions(b) }
    @message.update!(body: body)

    @message.broadcast_update
    @message.broadcast_mentionee_sidebar_updates
    deliver_webhooks_to_bots(@message, :updated)

    render json: { id: @message.id, body: { html: @message.body.body.to_s, plain: @message.plain_text_body } }
  end

  def destroy
    @message.deactivate
    @message.broadcast_remove
    deliver_webhooks_to_bots(@message, :deleted)

    head :no_content
  end

  private
    def set_own_message
      @room = Current.user.rooms.find(params[:room_id])
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
      body.to_s.gsub(/@\{(.+?)\}/) do |mention_sig|
        user_id = $1
        user = @room.users.find_by(id: user_id)
        user ? mention_user(user) : ""
      end
    end

    def mention_user(user)
      attachment_body = render_to_string partial: "users/mention", locals: { user: user }
      "<action-text-attachment sgid=\"#{user.attachable_sgid}\" content-type=\"application/vnd.sabha.mention\" content=\"#{attachment_body.gsub('"', '&quot;')}\"></action-text-attachment>"
    end

    def reading(io)
      io.rewind
      yield io.read.force_encoding("UTF-8")
    ensure
      io.rewind
    end

    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def not_found
      render json: { error: "Room or message not found", code: "not_found" }, status: :not_found
    end
end
