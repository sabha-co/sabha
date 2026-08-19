class Accounts::Bots::KeysController < ApplicationController
  before_action :ensure_can_manage_account

  def update
    @bot = User.active_bots.find(params[:bot_id])
    @bot.reset_bot_key

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_bots_url, notice: "New bearer key for #{@bot.name}" }
    end
  end
end
