# A per-forum, admin-curated label applied to that forum's posts. Modeled on
# Badge — a curated, named, colored entity — but scoped to a single forum:
# `room_id` points at the forum, and the STI `belongs_to :forum` means a tag
# whose room is not a forum fails validation, so tags can never leak across
# forums.
class Tag < ApplicationRecord
  belongs_to :forum, class_name: "Rooms::Forum", foreign_key: :room_id, inverse_of: :tags

  has_many :taggings, dependent: :delete_all
  has_many :posts, through: :taggings, source: :post

  validates :name, presence: true, length: { maximum: 30 }
  validates :name, uniqueness: { scope: :room_id, case_sensitive: false }
  validates :color, length: { maximum: 50 }, format: { with: /\A#[0-9A-Fa-f]{6}\z/, allow_blank: true }

  scope :ordered, -> { order(:name) }
end
