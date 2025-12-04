class Account < ApplicationRecord
  include Joinable, Deactivatable

  has_one_attached :logo
  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false

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
