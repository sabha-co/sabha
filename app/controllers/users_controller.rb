class UsersController < ApplicationController
  include NotifyBots

  require_unauthenticated_access only: %i[ new create ]

  before_action :set_user, only: :show
  before_action :verify_join_code, only: %i[ new create ]
  before_action :start_otp_if_user_exists, only: :create, if: -> { ENV["AUTH_METHOD"] == "otp" }

  def new
    @user = User.new
  end

  def create
    # Validate password for password-based authentication
    if ENV["AUTH_METHOD"] == "password"
      return unless validate_password_params
    end

    # If Gumroad is enabled, use that flow
    if ENV["GUMROAD_ON"] == "true"
      @user = User.from_gumroad_sale(user_params)

      if @user.nil?
        redirect_to account_join_code_url, alert: "We couldn't find a sale for that email. Please try a different email or contact #{BrandingConfig.support_email}."
        return
      end

      deliver_webhooks_to_bots(@user, :created) if @user.previously_new_record?
    else
      # Simple password-based creation (like Once-Campfire)
      @user = User.create!(user_params)
    end

    # Always require email verification for new users
    if @user.person? && !@user.verified?
      if ENV["AUTH_METHOD"] == "otp"
        # For OTP: Send verification code
        start_otp_for @user
        redirect_to new_auth_tokens_validations_path, notice: "Please check your email for a verification code."
      else
        # For password: Send verification email with link
        @user.send_verification_email
        redirect_to root_url, notice: "Please check your email to verify your account."
      end
    else
      start_new_session_for @user
      redirect_to root_url
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_url(email_address: user_params[:email_address])
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

    def validate_password_params
      @user = User.new

      if user_params[:password].blank?
        flash.now[:alert] = "Password can't be blank"
        render :new, status: :unprocessable_entity
        return false
      elsif user_params[:password].length < User::MINIMUM_PASSWORD_LENGTH
        flash.now[:alert] = "Password is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
        render :new, status: :unprocessable_entity
        return false
      end

      true
    end

    def user_params
      permitted_params = params.require(:user).permit(:name, :avatar, :email_address, :password)
      permitted_params[:email_address]&.downcase!
      permitted_params
    end
end
