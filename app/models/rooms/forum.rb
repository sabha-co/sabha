# A forum presents its posts as a gallery instead of a chat stream. Each post is
# an opening message plus a Rooms::Thread spawned on it for replies; the forum
# owns the per-forum tag set applied to those posts. Like an open room, a forum
# is a joinable sidebar room — but its opening posts do not ping every member.
class Rooms::Forum < Room
  # The forum owns its tag set; each tag's `room_id` points back here.
  has_many :tags, class_name: "Tag", foreign_key: :room_id, inverse_of: :forum, dependent: :destroy

  def applicable_activity_types(message)
    message.mentionees.any? ? [ :mention ] : []
  end
end
