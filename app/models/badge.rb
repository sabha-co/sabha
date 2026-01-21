class Badge < ApplicationRecord
  has_many :users, dependent: :nullify

  validates :name, presence: true, length: { maximum: 10 }
  validates :icon, length: { maximum: 50 }
  validates :color, length: { maximum: 50 }, format: { with: /\A#[0-9A-Fa-f]{6}\z/, allow_blank: true }

  scope :ordered, -> { order(:name) }
end
