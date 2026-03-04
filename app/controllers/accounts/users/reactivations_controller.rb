class Accounts::Users::ReactivationsController < ApplicationController
  before_action :ensure_can_administer

  def create
    @user = User.find(params[:user_id])

    if @user.reactivatable_by?(Current.user)
      @user.reactivate
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_users_url }
    end
  end
end
