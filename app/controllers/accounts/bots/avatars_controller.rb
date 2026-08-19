class Accounts::Bots::AvatarsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_bot

  def destroy
    @bot.avatar.purge
    redirect_to edit_account_bot_path(@bot)
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:bot_id])
    end
end
