class Accounts::JoinCodesController < ApplicationController
  before_action :ensure_can_administer

  def create
    Current.account.reset_join_code
    redirect_to account_url, notice: "New join link generated"
  end

  def update
    join_code = Current.account.toggle_join_code_expiration
    notice = join_code.expires? ? "Join link now #{join_code.expiry_display.downcase}" : "Join link will never expire"
    redirect_to account_url, notice: notice
  end
end
