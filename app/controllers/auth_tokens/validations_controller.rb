class AuthTokens::ValidationsController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, with: -> { head :too_many_requests }

  # Token-based login (magic link) is always allowed for Cloud bootstrap
  # Code-based OTP is only allowed when AUTH_METHOD=otp
  before_action :require_otp_or_token

  def new
  end

  def create
    auth_token = AuthToken.lookup(email_address: session[:otp_email_address], token: params[:token], code: params[:code])

    if auth_token
      auth_token.use!
      session.delete(:otp_email_address)

      # Verify email if not already verified (for new signups via OTP)
      auth_token.user.verify_email! unless auth_token.user.verified?

      start_new_session_for(auth_token.user)
      redirect_to post_authenticating_url, notice: "Welcome back to #{Branding.app_name}!"
    else
      redirect_to new_auth_tokens_validations_path, alert: "Invalid or expired token. Please try again."
    end
  end

  private

  def require_otp_or_token
    # Token-based login is always allowed (for Cloud bootstrap magic links)
    return if params[:token].present?

    # Code-based OTP is only allowed when AUTH_METHOD=otp
    if Current.account.auth_method_value != "otp"
      redirect_to new_session_url, alert: "OTP login is not enabled."
    end
  end
end
