# Join row linking a Tag to a post — a Rooms::Thread whose parent message lives
# in the tag's forum. Hard-deleted; carries no state of its own. The unique
# [tag_id, room_id] index keeps a post from carrying the same tag twice.
class Tagging < ApplicationRecord
  belongs_to :tag
  belongs_to :post, class_name: "Rooms::Thread", foreign_key: :room_id, inverse_of: :taggings

  validates :tag_id, uniqueness: { scope: :room_id }
end
