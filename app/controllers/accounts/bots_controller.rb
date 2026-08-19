class Accounts::BotsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_bot, only: %i[ show edit update destroy ]

  def index
    @bots = User.active_bots.ordered.includes(:webhook)
    @bot_invite_code = Current.account.active_bot_invite_code
  end

  def new
    @bot = User.active_bots.new
  end

  def create
    @bot = User.create_bot! bot_params
    redirect_to account_bot_url(@bot)
  rescue ActiveRecord::RecordInvalid => e
    @bot = e.record.is_a?(User) ? e.record : User.active_bots.new(bot_params.except(:webhook_url))
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  def show
    @rooms_count = @bot.room_memberships.count
  end

  def edit
  end

  def update
    @bot.update_bot! bot_params
    redirect_to account_bot_url(@bot)
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
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
