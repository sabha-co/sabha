class Messages::UnreadsController < ApplicationController
  before_action :set_message
  before_action :set_channel
  before_action :set_membership

  def create
    @membership.mark_unread_at(@message)
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    def set_channel
      @channel = Current.user.channels.find(params[:channel_id])
    end

    def set_membership
      @membership = Current.user.memberships.find_by!(channel_id: @channel.id)
    end
end
