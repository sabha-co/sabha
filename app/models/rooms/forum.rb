# A forum presents its posts as a gallery instead of a chat stream. Each post is
# a first-class Rooms::Post that belongs directly to the forum, its body the
# post's first message. Like an open room, a forum is a joinable sidebar room —
# but its posts do not ping every member, and joining does not fan a membership
# row out to every post: access derives from forum membership (see viewable_by?)
# and members follow individual posts lazily.
class Rooms::Forum < Room
  def applicable_activity_types(message)
    message.mentionees.any? ? [ :mention ] : []
  end

  # Forums render a gallery, not a chat stream: a forum owns no messages, so it
  # never receives one. (Posts and their replies live in Rooms::Post, which keeps
  # normal unread behavior.)
  def receive(message)
  end

  # A forum's posts derive their access from the forum: any active member can
  # view them, without a per-post membership row for every member. Rooms::Post
  # delegates its viewable_by? here (Fizzy: a Card delegates accessible_to? to
  # its Board).
  def viewable_by?(user)
    user.present? && memberships.active.exists?(user_id: user.id)
  end

  # Creates a post: a Rooms::Post that belongs to this forum, with its body as
  # message #1. Only the author gets a membership (involvement "everything" via
  # Rooms::Post#default_involvement) — a post does NOT fan a row out to every
  # forum member. Access derives from forum membership; other members follow
  # lazily (on reply, or via Follow). Runs in Current.user's context (the poster).
  def post!(title:, body:)
    attempts = 0
    begin
      transaction do
        Rooms::Post.create!(parent_room: self, name: title, creator: Current.user).tap do |post|
          post.memberships.grant_to(Current.user)
          post.messages.create!(body: body, creator: Current.user)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # Two posts with the same title can race the rooms.slug unique index. The
      # loser retries: unique_slug_from_title now sees the winner's slug and
      # picks the next suffix.
      raise if (attempts += 1) >= 3
      retry
    end
  end

  # Gallery posts: active posts, filtered by Solved state and sorted.
  #   - solved: "solved" | "open" | nil (all)
  #   - sort:   "recent" (default) | "newest"
  #
  # Queried by the denormalized parent_room_id FK (not a threads-through-messages
  # join) so the filter + sort ride a composite index — no filesort, the same way
  # a room's message stream sorts on (room_id, created_at).
  def posts(solved: nil, sort: nil)
    scope = Rooms::Post.active.where(parent_room_id: id)
    scope = scope.solved   if solved == "solved"
    scope = scope.unsolved if solved == "open"
    sort == "newest" ? scope.reverse_chronologically : scope.recently_active
  end

  # When a member leaves the forum — self-service (accept_leave!) or admin
  # removal (remove_member!) — drop the post Follows they opted into so reply
  # notifications stop for a forum they left. Access itself needs no cleanup: it
  # derives from forum membership. Runs as a job (Fizzy's clean_inaccessible_data
  # shape) because it can span many posts.
  def accept_leave!(user)
    super
    clean_up_post_follows_later(user)
  end

  def remove_member!(user, actor:)
    super
    clean_up_post_follows_later(user)
  end

  private
    def clean_up_post_follows_later(user)
      ForumFollowCleanupJob.perform_later(forum: self, user: user)
    end
end
