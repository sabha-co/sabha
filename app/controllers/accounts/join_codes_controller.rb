class Accounts::JoinCodesController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    Current.account.reset_join_code
    redirect_back fallback_location: account_url, notice: "New join link generated"
  end

  def update
    join_code = Current.account.toggle_join_code_expiration
    notice = join_code.expires? ? "This join link will #{join_code.expiry_display.sub("Expires", "expire")}" : "This join link will never expire"
    redirect_back fallback_location: account_url, notice: notice
  end
end
