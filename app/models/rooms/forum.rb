# A forum presents its posts as a gallery instead of a chat stream. Each post is
# an opening message plus a Rooms::Thread spawned on it for replies. Like an open
# room, a forum is a joinable sidebar room — but its opening posts do not ping
# every member.
class Rooms::Forum < Room
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
  # Rooms::Thread that *is* the post — titled and reply-able. Every forum member
  # gets access, mirroring how a thread inherits its parent room's members. Runs
  # in `Current.user`'s context (the poster).
  def post!(title:, body:)
    attempts = 0
    begin
      transaction do
        message = messages.create!(body: body)
        Rooms::Thread.create_for({ parent_message_id: message.id, name: title }, users: users)
      end
    rescue ActiveRecord::RecordNotUnique
      # Two posts with the same title can race the rooms.slug unique index. The
      # loser retries: unique_slug_from_title now sees the winner's slug and
      # picks the next suffix.
      raise if (attempts += 1) >= 3
      retry
    end
  end

  # Gallery posts: active post-threads, filtered by Solved state and sorted.
  #   - solved: "solved" | "open" | nil (all)
  #   - sort:   "recent" (default) | "newest"
  def posts(solved: nil, sort: nil)
    scope = threads.active
    scope = scope.solved   if solved == "solved"
    scope = scope.unsolved if solved == "open"
    sort == "newest" ? scope.reverse_chronologically : scope.recently_active
  end
end
