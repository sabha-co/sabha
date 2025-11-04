class Account < ApplicationRecord
  include Joinable, Deactivatable

  has_one_attached :logo

  # Validations for admin settings
  validates :auth_method, inclusion: { in: %w[password otp], message: "must be 'password' or 'otp'" }, allow_nil: true

  # Helper methods for settings (database only, with defaults from migration)
  def auth_method_value
    auth_method || "password"
  end

  def open_registration_value
    open_registration || false
  end
end
