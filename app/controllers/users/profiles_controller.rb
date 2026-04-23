class Users::ProfilesController < ApplicationController
  before_action :set_user

  def show
    @shared_memberships = Current.user.memberships.shared.with_ordered_room
    @direct_memberships = Current.user.memberships.visible.direct_rooms.with_ordered_room
  end

  def update
    if email_change_requested?
      handle_email_change
    else
      @user.update user_params.except(:email_address)
      redirect_to after_update_url, notice: update_notice
    end
  end

  private
    def set_user
      @user = Current.user
    end

    def user_params
      params.require(:user).permit(:name, :avatar, :email_address, :password, :bio, :twitter_url, :linkedin_url, :personal_url).compact
    end

    def email_change_requested?
      return false if Sabha.saas?  # SaaS mode: email changes via GlobalIdentity profile only

      new_email = user_params[:email_address]
      new_email.present? && new_email.downcase != @user.email_address
    end

    def handle_email_change
      new_email = user_params[:email_address]
      @user.update user_params.except(:email_address)

      if @user.update_email(new_email)
        redirect_to user_profile_url, notice: "A verification email has been sent to #{@user.unconfirmed_email}. Please check your inbox to confirm the change."
      else
        redirect_to user_profile_url, alert: @user.errors.full_messages.to_sentence
      end
    end

    def after_update_url
      name_changed_from_default? ? root_url : user_profile_url
    end

    def name_changed_from_default?
      @user.name_previously_was == User::DEFAULT_NAME && @user.saved_change_to_name?
    end

    def update_notice
      params[:user][:avatar] ? "It may take up to 30 minutes to change everywhere." : "✓"
    end
end
