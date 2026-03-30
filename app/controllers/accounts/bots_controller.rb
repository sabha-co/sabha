class Accounts::BotsController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_bot, only: %i[ show edit update destroy ]

  def index
    @bots = User.active_bots.ordered
  end

  def new
    @bot = User.active_bots.new
  end

  def create
    @bot = User.create_bot! bot_params
    redirect_to account_bot_url(@bot)
  end

  def show
    @rooms = Room.active.without_directs.without_threads.ordered
    @bot_memberships = @bot.memberships.visible.index_by(&:room_id)
  end

  def edit
    @rooms = Room.active.without_directs.without_threads.ordered
    @bot_memberships = @bot.memberships.visible.index_by(&:room_id)
  end

  def update
    @bot.update_bot! bot_params
    redirect_to account_bot_url(@bot)
  end

  def destroy
    @bot.deactivate
    redirect_to account_bots_url
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:id])
    end

    def bot_params
      params.require(:user).permit(:name, :avatar, :webhook_url)
    end
end
