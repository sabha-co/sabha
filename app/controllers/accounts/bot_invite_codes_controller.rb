class Accounts::BotInviteCodesController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    @bot_invite_code, @regenerated = Current.account.generate_bot_invite_code!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_bots_url }
    end
  end
end
