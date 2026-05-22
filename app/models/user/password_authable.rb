module User::PasswordAuthable
  extend ActiveSupport::Concern

  included do
    has_secure_password validations: false
    validates :password, length: { minimum: User::MINIMUM_PASSWORD_LENGTH }, if: -> { password.present? }

    generates_token_for :password_reset, expires_in: 1.hour do
      password_salt&.last(10)
    end
  end

  def send_password_reset_email
    UserMailer.password_reset(self).deliver_later
  end
end
