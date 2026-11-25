class Accounts::Bots::ChannelPermissionsController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_bot
  before_action :set_channel, except: :index

  def index
    @bot_memberships = @bot.channel_memberships.includes(:channel).order("channels.sortable_name")
    @available_channels = @bot.channels_available_to_add
  end

  def show
    @membership = @bot.memberships.visible.find_by(channel: @channel)
  end

  def create
    @channel.add_member!(@bot, actor: Current.user)
    redirect_to account_bot_channel_permission_path(@bot, @channel)
  end

  def update
    @bot.memberships.find_by!(channel: @channel).update!(involvement: params[:involvement])
    redirect_to account_bot_channel_permission_path(@bot, @channel)
  end

  def destroy
    @channel.remove_member!(@bot, actor: Current.user)
    redirect_to account_bot_channel_permission_path(@bot, @channel)
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:bot_id])
    end

    def set_channel
      @channel = Channel.active.without_directs.without_threads.find(params[:channel_id])
    end
end
