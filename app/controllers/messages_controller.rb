class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, ChannelScoped, NotifyBots, SubChannelAccessible

  skip_before_action :set_channel
  before_action :set_channel, only: %i[ index destroy ]
  before_action :set_channel_if_found, only: %i[ show edit update ]
  before_action :set_message, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]

  layout false, only: :index

  def index
    @messages = find_paged_messages

    head :no_content if @messages.blank?
  end

  def create
    set_channel
    @message = @channel.messages.create_with_attachment!(message_params)

    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)
  rescue ActiveRecord::RecordInvalid
    render action: :not_allowed
  rescue ActiveRecord::RecordNotFound
    render action: :channel_not_found
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

    redirect_to @channel ? channel_message_url(@channel, @message) : @message
  end

  def destroy
    # A post's opening message is its body — deleting it alone would orphan a
    # bodyless post. Delete the whole post instead (Channels::Forums::PostsController).
    return head :forbidden if @channel.post? && @channel.opening_message?(@message)

    @message.deactivate
    @message.broadcast_remove
    notify_bots(@message, :deleted)
  end

  private
    # Fall back to parent-derived access for a sub-channel when there's no direct
    # membership, then re-check so a stale membership can't keep granting it.
    def set_channel
      @membership = Current.user.memberships.find_by(channel_id: params[:channel_id])
      @channel = deny_stale_sub_channel(@membership&.channel || viewable_sub_channel(params[:channel_id]))
      raise ActiveRecord::RecordNotFound unless @channel
    end

    def set_message
      if @channel
        @message = @channel.messages.find(params[:id])
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
      scope = @channel.messages.with_thread_summary.with_creator.with_bookmark_status_for(Current.user)

      messages = if params[:before].present?
        anchor = @channel.messages.find_by(id: params[:before])
        anchor ? scope.page_before(anchor) : Message.none
      elsif params[:after].present?
        anchor = @channel.messages.find_by(id: params[:after])
        anchor ? scope.page_after(anchor) : Message.none
      else
        scope.last_page
      end

      Message.with_thread_participants(prepend_thread_parent(messages))
    end

    def prepend_thread_parent(messages)
      return messages unless @channel.thread? && messages.any? && @channel.parent_message.present?

      first_thread_message = @channel.messages.ordered.first
      messages_array = messages.to_a

      if messages_array.first&.id == first_thread_message&.id
        [ @channel.parent_message ] + messages_array
      else
        messages_array
      end
    end
end
