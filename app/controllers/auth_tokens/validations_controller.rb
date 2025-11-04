class AuthTokens::ValidationsController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, with: -> { render_rejection :too_many_requests }

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
      redirect_to post_authenticating_url
    else
      redirect_to new_auth_tokens_validations_path, alert: "Invalid or expired token. Please try again."
    end
  end
end
