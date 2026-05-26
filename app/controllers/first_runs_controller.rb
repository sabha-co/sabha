class FirstRunsController < ApplicationController
  allow_unauthenticated_access

  before_action :prevent_repeats
  before_action :route_through_sso_when_bootstrapping, if: -> { FirstRun.should_auto_bootstrap? }

  def show
    @user = User.new
  end

  def create
    user = FirstRun.create!(user_params)
    start_new_session_for user

    redirect_to root_url
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_url
  rescue ActiveRecord::RecordInvalid => e
    @user = e.record.is_a?(User) ? e.record : User.new
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end

  private
    def prevent_repeats
      redirect_to root_url if Account.any?
    end

    def route_through_sso_when_bootstrapping
      redirect_to sso_handshake_url
    end

    def user_params
      params.require(:user).permit(:name, :avatar, :email_address, :password)
    end
end
