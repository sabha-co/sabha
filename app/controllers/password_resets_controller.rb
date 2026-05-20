class PasswordResetsController < ApplicationController
  include PasswordValidation

  layout "session", only: %i[ new edit update ]

  require_unauthenticated_access only: %i[ new ]
  allow_unauthenticated_access only: %i[ create edit update ]
  rate_limit to: 3, within: 1.minute, only: :create, with: -> { redirect_to new_password_reset_path, alert: "Too many requests. Please wait before trying again." }

  before_action :require_password_auth

  def new
    store_return_to
  end

  def create
    @user = User.find_by(email_address: params[:email_address])

    if @user
      # Send password reset email (this will also help unverified users)
      @user.send_password_reset_email
      redirect_to new_session_path, notice: "Password reset instructions sent to #{@user.email_address}. Please check your inbox."
    else
      # Don't reveal whether the email exists or not
      redirect_to new_session_path, notice: "If that email address is in our system, you will receive password reset instructions."
    end
  end

  def edit
    @user = User.find_by_token_for(:password_reset, params[:token])

    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired password reset link."
    end
  end

  def update
    @user = User.find_by_token_for(:password_reset, params[:token])

    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired password reset link."
      return
    end

    if (error = validate_password_params)
      return render_password_error(error)
    end

    if @user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      # Verify email if not already verified
      @user.verify_email! unless @user.verified?

      start_new_session_for @user
      redirect_to post_authenticating_url, notice: "Your password has been reset successfully!"
    else
      render_password_error(@user.errors.full_messages.to_sentence)
    end
  end

  private

  def require_password_auth
    unless Current.account.password_auth?
      redirect_to new_session_url, alert: "Password reset is not available."
    end
  end
end
