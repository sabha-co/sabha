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

      if Current.account.sso_auth?
        redirect_to sso_handshake_url, notice: "Email verified. Please sign in."
      else
        start_new_session_for @user
        redirect_to root_url, notice: "Email verified successfully! Welcome to #{Branding.contextual_app_name}."
      end
    end
  end

  def confirm_email_change
    @user = User.find_by_token_for(:email_change, params[:token])

    if @user.nil?
      redirect_to root_url, alert: "Invalid or expired email change link."
    elsif @user.unconfirmed_email.blank?
      redirect_to root_url, notice: "Email change already confirmed or cancelled."
    else
      @user.confirm_email_change!
      redirect_to root_url, notice: "Your email has been successfully updated to #{@user.email_address}."
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
