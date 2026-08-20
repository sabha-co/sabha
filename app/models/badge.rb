class Badge < ApplicationRecord
  # Suggested palette (contrast-checked against the 14% chip fill) and the
  # default hue. Colour is a free picker, so any hex validates.
  COLORS = %w[ #8257E0 #4F52D9 #1B8F53 #B4730C #C7443F #12A594 #E0407A #2F6FEB ].freeze
  DEFAULT_COLOR = "#8257E0"

  has_many :users, dependent: :nullify

  attribute :color, default: DEFAULT_COLOR

  normalizes :name, with: ->(name) { name.strip.upcase }

  validates :name, presence: true, length: { maximum: 10 }, uniqueness: { case_sensitive: false }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }

  scope :ordered, -> { order(:id) }
end
