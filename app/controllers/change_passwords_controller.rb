class ChangePasswordsController < ApplicationController
  include PasswordValidation

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

    if (error = validate_password_params)
      return render_password_error(error, template: :show)
    end

    if params[:password] == ENV["ADMIN_PASSWORD"]
      return render_password_error("Please choose a different password than the temporary one", template: :show)
    end

    if @user.update(password: params[:password], must_change_password: false)
      redirect_to root_path, notice: "Password changed successfully!"
    else
      render_password_error(@user.errors.full_messages.to_sentence, template: :show)
    end
  end
end
