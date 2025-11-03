class AuthTokensController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, with: -> { render_rejection :too_many_requests }

  before_action :set_user

  def create
    session[:otp_email_address] = params[:email_address]

    auth_token = @user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    auth_token.deliver_later

    redirect_to new_auth_tokens_validations_path
  end

  private

  def set_user
    @user = User.find_by(email_address: params[:email_address].downcase) if params[:email_address].present?

    unless @user
      redirect_to new_session_url, alert: "We couldn't find an account with that email. Please try a different email or contact #{BrandingConfig.support_email}."
    end
  end
end
