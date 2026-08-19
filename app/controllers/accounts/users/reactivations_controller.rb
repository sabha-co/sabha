class Accounts::Users::ReactivationsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    @user = User.find(params[:user_id])

    if @user.reactivatable_by?(Current.user)
      @user.reactivate
    end

    respond_to do |format|
      format.turbo_stream do
        if turbo_frame_request?
          render :create
        else
          redirect_to user_url(@user)
        end
      end
      format.html { redirect_to account_users_url }
    end
  end
end
