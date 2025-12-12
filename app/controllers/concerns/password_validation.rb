module PasswordValidation
  extend ActiveSupport::Concern

  private

  def validate_password_params
    if params[:password].blank?
      "Password can't be blank"
    elsif params[:password].length < User::MINIMUM_PASSWORD_LENGTH
      "Password is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
    elsif params[:password] != params[:password_confirmation]
      "Password confirmation doesn't match password"
    end
  end

  def render_password_error(error, template: :edit)
    flash.now[:alert] = error
    render template, status: :unprocessable_entity
  end
end
