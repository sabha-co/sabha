class Account < ApplicationRecord
  include Joinable, Deactivatable

  has_one_attached :logo
  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false

  # Validations for admin settings
  validates :auth_method, inclusion: { in: %w[password otp], message: "must be 'password' or 'otp'" }, allow_nil: true

  # Helper method for auth_method with default
  def auth_method_value
    auth_method || "password"
  end
end
