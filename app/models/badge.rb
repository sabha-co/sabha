class Badge < ApplicationRecord
  # Colour is a free picker, so any hex validates; new badges start on this hue.
  DEFAULT_COLOR = "#8257E0"

  has_many :users, dependent: :nullify

  attribute :color, default: DEFAULT_COLOR

  normalizes :name, with: ->(name) { name.strip.upcase }

  validates :name, presence: true, length: { maximum: 10 }, uniqueness: { case_sensitive: false }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }

  scope :ordered, -> { order(:id) }
end
