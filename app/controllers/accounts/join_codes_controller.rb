class Accounts::JoinCodesController < ApplicationController
  before_action :ensure_can_administer

  def create
    Current.account.reset_join_code
    redirect_to account_url
  end

  def update
    Current.account.toggle_join_code_expiration
    redirect_to account_url
  end
end
