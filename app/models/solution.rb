# A forum post's Solved state, modeled as a record instead of a timestamp
# column: a Solution exists iff the post is solved, and it carries who marked it
# and when. Rooms::Post#solved? derives from its
# presence, and the gallery's solved/unsolved filters are joins(:solution) /
# where.missing(:solution).
class Solution < ApplicationRecord
  belongs_to :post, class_name: "Rooms::Post", touch: true
  belongs_to :user, default: -> { Current.user }
end
