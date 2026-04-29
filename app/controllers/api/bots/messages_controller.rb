class API::Bots::MessagesController < API::Bots::BaseController
  include ActiveStorage::SetCurrent, NotifyBots, CursorPaginated

  before_action :set_room, only: %i[index create]
  before_action :parse_pagination_params, only: :index
  before_action :set_message, :require_message_creator, only: %i[update destroy]

  rescue_from Rooms::Thread::NestedThreadError, with: :nested_thread_invalid

  def index
    scope = @room.messages.active
                 .with_rich_text_body_and_embeds
                 .with_creator
                 .with_attached_attachment
                 .reorder(created_at: :desc, id: :desc)
    scope = scope.since(@after_time) if @after_time
    scope = if @before_id
      scope.before_cursor(@before_time, @before_id)
    elsif @before_time
      scope.created_before(@before_time)
    else
      scope
    end
    scope = scope.limit(@limit + 1)

    messages = scope.to_a
    @has_more = messages.size > @limit
    @messages = messages.first(@limit)
    @next_cursor = build_cursor(@messages.last) if @has_more
  end

  def show
    @message = Message.active
                      .where(room_id: Current.user.rooms.select(:id))
                      .with_rich_text_body_and_embeds
                      .with_creator
                      .with_attached_attachment
                      .find(params[:id])
  end

  def create
    target_room = resolve_target_room
    @message = target_room.messages.create_with_attachment(message_params)

    if @message.persisted?
      @message.broadcast_create
      @message.broadcast_mentionee_sidebar_updates
      notify_bots(@message, :created)

      render json: { id: @message.id, room_id: target_room.id },
             status: :created,
             location: room_message_url(target_room, @message)
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

    def resolve_target_room
      return @room if params[:parent_message_id].blank?
      Rooms::Thread.find_or_create_for(parent_message_in_room, users: @room.users)
    end

    # Scoping through @room.messages enforces the API contract that
    # parent_message_id must reference a message in the URL room — cross-room
    # references 404 here.
    def parent_message_in_room
      @room.messages.active.find(params[:parent_message_id])
    end

    def nested_thread_invalid
      render json: { error: "parent_message_id cannot point at a message inside an existing thread", code: "validation_failed" },
             status: :unprocessable_entity
    end

    def set_message
      @message = Message.active.where(room_id: Current.user.rooms.select(:id)).find(params[:id])
      @room = @message.room
    end

    def require_message_creator
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
end
