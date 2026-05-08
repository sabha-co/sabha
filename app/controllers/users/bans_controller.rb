class Users::BansController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_user

  def create
    return redirect_to @user, alert: ban_rejection_alert unless @user.bannable_by?(Current.user)
    @user.ban
    redirect_to @user
  end

  def destroy
    return redirect_to @user, alert: unban_rejection_alert unless @user.unbannable_by?(Current.user)
    @user.unban
    redirect_to @user
  end

  private
    def set_user
      @user = User.find(params[:user_id])
    end

    def ban_rejection_alert
      if @user == Current.user
        "You can't ban yourself."
      elsif @user.banned?
        "#{@user.name} is already banned."
      end
    end

    def unban_rejection_alert
      if @user == Current.user
        "You can't unban yourself."
      elsif !@user.banned?
        "#{@user.name} is not banned."
      end
    end
end
