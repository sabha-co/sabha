class AuthTokensController < ApplicationController
  include EmailValidation

  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, with: -> { head :too_many_requests }

  before_action :require_otp_auth
  before_action :validate_email_param
  before_action :set_user

  def create
    session[:otp_email_address] = params[:email_address]

    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    auth_token.deliver_later

    redirect_to new_auth_tokens_validations_path
  end

  private

  def require_otp_auth
    if Current.account.auth_method_value != "otp"
      redirect_to new_session_url, alert: "OTP login is not enabled."
    end
  end

  def validate_email_param
    render_invalid_email unless valid_email?(params[:email_address])
  end

  def set_user
    @user = User.find_by(email_address: params[:email_address].downcase)

    unless @user
      redirect_to new_session_url, alert: "We couldn't find an account with that email. Please try a different email or contact #{Branding.support_email}."
    end
  end
end
