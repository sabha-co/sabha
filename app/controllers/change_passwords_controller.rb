class ChangePasswordsController < ApplicationController
  # Skip the force password change check for this controller (would cause redirect loop)
  skip_before_action :require_password_change

  def show
    @user = Current.user

    # Redirect if user doesn't need to change password
    redirect_to root_path unless @user&.must_change_password?
  end

  def update
    @user = Current.user

    unless @user&.must_change_password?
      redirect_to root_path
      return
    end

    if params[:password].blank?
      flash.now[:alert] = "Password can't be blank"
      render :show, status: :unprocessable_entity
    elsif params[:password].length < User::MINIMUM_PASSWORD_LENGTH
      flash.now[:alert] = "Password is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
      render :show, status: :unprocessable_entity
    elsif params[:password] != params[:password_confirmation]
      flash.now[:alert] = "Password confirmation doesn't match password"
      render :show, status: :unprocessable_entity
    elsif params[:password] == ENV["ADMIN_PASSWORD"]
      # Prevent user from keeping the temporary password
      flash.now[:alert] = "Please choose a different password than the temporary one"
      render :show, status: :unprocessable_entity
    elsif @user.update(password: params[:password], must_change_password: false)
      redirect_to root_path, notice: "Password changed successfully!"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end
end
