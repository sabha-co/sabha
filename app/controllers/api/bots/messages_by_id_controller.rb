class API::Bots::MessagesByIdController < API::Bots::BaseController
  include ActiveStorage::SetCurrent, NotifyBots

  before_action :set_message_with_access_check
  before_action :enforce_ownership

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
    def set_message_with_access_check
      @message = Message.active
                        .where(room_id: Current.user.rooms.select(:id))
                        .find(params[:id])
      @room = @message.room
    end

    def enforce_ownership
      head :forbidden unless @message.creator_id == Current.user.id
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
end
