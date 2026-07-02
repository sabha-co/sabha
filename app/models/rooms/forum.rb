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

  # Opening posts are gallery entries, not chat messages: creating one must not
  # mark the forum unread for other members or bump chat counters. (Replies live
  # in the post-thread, which keeps normal unread behavior.) The gallery surfaces
  # new posts by activity order, not by an unread badge on the forum.
  def receive(message)
  end

  # Creates a post: an opening message that holds the body, plus the
  # Rooms::Thread that *is* the post — titled, tagged, and reply-able. Every
  # forum member gets access, mirroring how a thread inherits its parent room's
  # members. Runs in `Current.user`'s context (the poster).
  def post!(title:, body:, tag_ids: [])
    transaction do
      message = messages.create!(body: body)
      post = Rooms::Thread.create_for({ parent_message_id: message.id, name: title }, users: users)
      post.tag_ids = scoped_tag_ids(tag_ids)
      post
    end
  end

  SORTS = { "recent" => "rooms.last_active_at DESC", "newest" => "rooms.created_at DESC" }.freeze

  # Gallery posts: active post-threads, filtered and sorted for the gallery.
  #   - tag_ids: keep posts carrying ANY of these tags (OR semantics — the
  #     intuitive "show me posts tagged X or Y"). Foreign tag ids simply match
  #     nothing, since the base scope is already this forum's threads.
  #   - solved: "solved" | "open" | nil (all)
  #   - sort:   "recent" (default) | "newest"
  def posts(tag_ids: nil, solved: nil, sort: nil)
    scope = threads.active
    scope = scope.where(id: Tagging.where(tag_id: tag_ids).select(:room_id)) if tag_ids.present?
    scope = scope.where.not(solved_at: nil) if solved == "solved"
    scope = scope.where(solved_at: nil)     if solved == "open"
    scope.order(Arel.sql(SORTS.fetch(sort, SORTS["recent"])))
  end

  # Replace a post's tags, keeping only tags that belong to this forum (R8 edit).
  def apply_tags(post, tag_ids)
    post.tag_ids = scoped_tag_ids(tag_ids)
  end

  # Seed the forum's tag set from a comma-separated list (used at creation).
  # Blank/duplicate names are ignored; invalid names are skipped silently.
  def create_tags_from_list(list)
    list.to_s.split(",").map(&:strip).reject(&:blank?).uniq.each do |name|
      tags.create(name: name)
    end
  end

  private
    # Keep only tag ids that belong to THIS forum, so a crafted request can't
    # attach another forum's tag to a post here.
    def scoped_tag_ids(tag_ids)
      tags.where(id: Array(tag_ids)).pluck(:id)
    end
end
