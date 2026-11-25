# Self-service join/leave — users manage their own membership.
# See also Channels::MembersController for admin roster management.
class Channels::MembershipsController < ApplicationController
  include ChannelScoped

  skip_before_action :set_channel, only: :create
  before_action :set_joinable_channel, only: :create
  before_action :ensure_not_direct_channel, only: :destroy

  def create
    @channel.accept_join!(Current.user)
    broadcast_sidebar_channel_added(Current.user, @channel)

    redirect_to channel_url(@channel), notice: "Joined #{@channel.name}"
  end

  def destroy
    @channel.accept_leave!(Current.user)
    broadcast_sidebar_channel_removed(Current.user, @channel)

    redirect_to root_url, notice: "You left #{@channel.name}"
  rescue Membership::LastVisibleMemberError
    redirect_back fallback_location: channel_url(@channel),
                  alert: "You're the last member. Delete the channel instead."
  end

  private
    def set_joinable_channel
      @channel = Channel.active.where(type: %w[ Channels::Open Channels::Forum ]).find(params[:channel_id])
    end

    def ensure_not_direct_channel
      redirect_to channel_url(@channel), alert: "Cannot leave direct messages" if @channel.direct?
    end
end
