class AuthTokens::ValidationsController < ApplicationController
  include BlockBannedRequests

  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, with: -> { head :too_many_requests }

  before_action :reject_banned_ip, only: :create
  before_action :redirect_to_saas_login, if: -> { Sabha.saas? }

  # Token-based login (magic link) is always allowed for Cloud bootstrap
  # Code-based OTP is only allowed when AUTH_METHOD=otp
  before_action :require_otp_or_token

  def new
  end

  def create
    auth_token = AuthToken.lookup(email_address: session[:otp_email_address], token: params[:token], code: params[:code])

    if auth_token && auth_token.user.active?
      auth_token.use!
      session.delete(:otp_email_address)

      # Verify email if not already verified (for new signups via OTP)
      auth_token.user.verify_email! unless auth_token.user.verified?

      start_new_session_for(auth_token.user)
      redirect_to post_authenticating_url, notice: "Welcome back to #{Branding.contextual_app_name}!"
    else
      redirect_to new_auth_tokens_validations_path, alert: "Invalid or expired token. Please try again."
    end
  end

  private

  def redirect_to_saas_login
    # In SaaS mode, workspace login pages redirect to the global SaaS login
    redirect_to "/session/new"
  end

  def require_otp_or_token
    # Token-based login is always allowed (for Cloud bootstrap magic links)
    return if params[:token].present?

    # Code-based OTP is only allowed when AUTH_METHOD=otp
    if Current.account.auth_method_value != "otp"
      redirect_to new_session_url, alert: "OTP login is not enabled."
    end
  end
end
