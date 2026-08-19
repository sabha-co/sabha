class Accounts::Bots::KeysController < ApplicationController
  before_action :ensure_can_manage_account

  def update
    User.active_bots.find(params[:bot_id]).reset_bot_key
    redirect_to account_bots_url
  end
end
