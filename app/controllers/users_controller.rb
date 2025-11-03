class UsersController < ApplicationController
  include NotifyBots

  require_unauthenticated_access only: %i[ new create ]

  before_action :set_user, only: :show
  before_action :verify_join_code, only: %i[ new create ]
  before_action :start_otp_if_user_exists, only: :create

  def new
    @user = User.new
  end

  def create
    @user = User.from_gumroad_sale(user_params)

    if @user.nil?
      redirect_to account_join_code_url, alert: "We couldn't find a sale for that email. Please try a different email or contact #{BrandingConfig.support_email}."
      return
    end

    deliver_webhooks_to_bots(@user, :created) if @user.previously_new_record?

    if @user.previously_new_record? || @user.imported_from_gumroad_and_unclaimed?
      start_new_session_for @user
      redirect_to root_url
    else
      start_otp_for @user
      redirect_to new_auth_tokens_validations_path
    end
  end

  def show
    @recent_messages = Current.user.reachable_messages.created_by(@user).with_creator.ordered.last(5).reverse
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    def verify_join_code
      head :not_found if Current.account.join_code != params[:join_code]
    end

    def start_otp_if_user_exists
      user = User.active.non_suspended.find_by(email_address: user_params[:email_address])

      if user&.ever_authenticated?
        start_otp_for user
        redirect_to new_auth_tokens_validations_path
      end
    end

    def start_otp_for(user)
      session[:otp_email_address] = user.email_address

      auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
      auth_token.deliver_later
    end

    def user_params
      permitted_params = params.require(:user).permit(:name, :avatar, :email_address)
      permitted_params[:email_address]&.downcase!
      permitted_params
    end
end
