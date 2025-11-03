class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: { scope: :blocker_id }
  validate :unable_to_block_self

  private

  def unable_to_block_self
    errors.add(:blocked_id, "can't be the same as blocker") if blocker_id == blocked_id
  end
end
