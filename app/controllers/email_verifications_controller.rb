class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 3, within: 1.minute, only: :resend, with: -> { redirect_to root_url, alert: "Too many requests. Please wait before trying again." }

  def show
    @user = User.find_by_token_for(:email_verification, params[:token])

    if @user.nil?
      redirect_to root_url, alert: "Invalid or expired verification link."
    elsif @user.verified?
      redirect_to root_url, notice: "Your email is already verified. Please sign in."
    else
      @user.verify_email!
      start_new_session_for @user
      redirect_to root_url, notice: "Email verified successfully! Welcome to #{BrandingConfig.app_name}."
    end
  end

  def resend
    @user = User.find_by(email_address: params[:email_address])

    if @user && !@user.verified?
      @user.send_verification_email
      redirect_to new_session_url, notice: "Verification email sent to #{@user.email_address}. Please check your inbox."
    elsif @user&.verified?
      redirect_to new_session_url, notice: "Your email is already verified. Please sign in."
    else
      redirect_to new_session_url, alert: "Unable to resend verification email."
    end
  end
end
