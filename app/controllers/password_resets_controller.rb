class PasswordResetsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 3, within: 1.minute, only: :create, with: -> { redirect_to new_password_reset_path, alert: "Too many requests. Please wait before trying again." }

  def new
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

    # Validate password manually since has_secure_password validations are disabled
    if params[:password].blank?
      flash.now[:alert] = "Password can't be blank"
      render :edit, status: :unprocessable_entity
    elsif params[:password].length < User::MINIMUM_PASSWORD_LENGTH
      flash.now[:alert] = "Password is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
      render :edit, status: :unprocessable_entity
    elsif params[:password] != params[:password_confirmation]
      flash.now[:alert] = "Password confirmation doesn't match Password"
      render :edit, status: :unprocessable_entity
    elsif @user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      # Verify email if not already verified
      @user.verify_email! unless @user.verified?

      start_new_session_for @user
      redirect_to root_path, notice: "Your password has been reset successfully!"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
