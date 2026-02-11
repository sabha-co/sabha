class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, RoomScoped, NotifyBots

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
    @message = @room.messages.create_with_attachment(message_params)

    if @message.persisted?
      @message.broadcast_create
      @message.broadcast_mentionee_sidebar_updates
      deliver_webhooks_to_bots(@message, :created)
    else
      render action: :not_allowed
    end
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
    deliver_webhooks_to_bots(@message, :updated)

    redirect_to @room ? room_message_url(@room, @message) : @message
  end

  def destroy
    @message.deactivate
    @message.broadcast_remove
    deliver_webhooks_to_bots(@message, :deleted)
  end

  private
    def set_message
      if @room
        @message = @room.messages.find(params[:id])
      else
        @message = Current.user.reachable_messages.find(params[:id])
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
        scope.page_before(@room.messages.find(params[:before]))
      elsif params[:after].present?
        scope.page_after(@room.messages.find(params[:after]))
      else
        scope.last_page
      end

      prepend_thread_parent(messages)
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
