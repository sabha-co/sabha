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
    @message = @room.messages.create_with_attachment!(message_params)

    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)
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
    return head :forbidden if @room.is_a?(Rooms::Post) && @room.opening_message?(@message)

    @message.deactivate
    @message.broadcast_remove
    notify_bots(@message, :deleted)
  end

  private
    # A forum post derives access from its forum: a member can read and reply to
    # a post without a per-post membership (one is created lazily on reply). So
    # fall back to forum-derived access when there's no direct membership — and,
    # crucially, re-check viewable_by? even when a (possibly stale) post
    # membership resolved the room, so a member removed from the forum loses post
    # access immediately rather than riding an orphaned membership row.
    def set_room
      @membership = Current.user.memberships.find_by(room_id: params[:room_id])
      @room = @membership&.room || viewable_forum_post(params[:room_id])
      @room = nil if @room.is_a?(Rooms::Post) && !@room.viewable_by?(Current.user)
      raise ActiveRecord::RecordNotFound unless @room
    end

    def viewable_forum_post(room_id)
      post = Rooms::Post.active.find_by(id: room_id)
      post if post&.viewable_by?(Current.user)
    end

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
