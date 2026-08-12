class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, RoomScoped, NotifyBots, SubRoomAccessible

  skip_before_action :set_room
  before_action :set_room, only: %i[ index destroy ]
  before_action :set_room_if_found, only: %i[ show edit update ]
  before_action :set_message, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]

  layout false, only: :index

  def index
    @messages = find_paged_messages

    head :no_content if @messages.blank?
  end

  def create
    set_room
    @message = @room.messages.create_with_attachment!(message_params)

    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)
  rescue ActiveRecord::RecordNotUnique
    # A replayed send (retry after a lost response): the message already
    # exists, so answer with it again without re-broadcasting.
    @message = @room.messages.find_by!(client_message_id: message_params[:client_message_id])
    render :create
  rescue ActiveRecord::RecordInvalid
    render action: :not_allowed
  rescue ActiveRecord::RecordNotFound
    render action: :room_not_found
  end

  def show
  end

  def edit
  end

  def update
    @message.update!(message_params)

    @message.broadcast_update
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :updated)

    redirect_to @room ? room_message_url(@room, @message) : @message
  end

  def destroy
    # A post's opening message is its body — deleting it alone would orphan a
    # bodyless post. Delete the whole post instead (Rooms::Forums::PostsController).
    return head :forbidden if @room.post? && @room.opening_message?(@message)

    @message.deactivate
    @message.broadcast_remove
    notify_bots(@message, :deleted)
  end

  private
    # Fall back to parent-derived access for a sub-room when there's no direct
    # membership, then re-check so a stale membership can't keep granting it.
    def set_room
      @membership = Current.user.memberships.find_by(room_id: params[:room_id])
      @room = deny_stale_sub_room(@membership&.room || viewable_sub_room(params[:room_id]))
      raise ActiveRecord::RecordNotFound unless @room
    end

    def set_message
      if @room
        @message = @room.messages.find(params[:id])
      else
        @message = Current.user.reachable_message(params[:id])
      end
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@message)
    end

    def message_params
      params.require(:message).permit(:body, :attachment, :client_message_id)
    end

    def find_paged_messages
      scope = @room.messages.with_thread_summary.with_creator.with_bookmark_status_for(Current.user)

      messages = if params[:before].present?
        anchor = @room.messages.find_by(id: params[:before])
        anchor ? scope.page_before(anchor) : Message.none
      elsif params[:after].present?
        anchor = @room.messages.find_by(id: params[:after])
        anchor ? scope.page_after(anchor) : Message.none
      else
        scope.last_page
      end

      Message.with_thread_participants(prepend_thread_parent(messages))
    end

    def prepend_thread_parent(messages)
      return messages unless @room.thread? && messages.any? && @room.parent_message.present?

      first_thread_message = @room.messages.ordered.first
      messages_array = messages.to_a

      if messages_array.first&.id == first_thread_message&.id
        [ @room.parent_message ] + messages_array
      else
        messages_array
      end
    end
end
