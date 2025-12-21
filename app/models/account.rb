class Account < ApplicationRecord
  include Joinable, Deactivatable

  VALID_AUTH_METHODS = %w[password otp].freeze

  has_one_attached :logo
  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false

  # Auth method is controlled via ENV["AUTH_METHOD"]
  # Valid values: "password" (default), "otp"
  def auth_method_value
    value = ENV["AUTH_METHOD"] || "password"
    value.in?(VALID_AUTH_METHODS) ? value : "password"
  end
end
