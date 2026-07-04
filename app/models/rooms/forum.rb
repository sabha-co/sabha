# A forum presents its posts as a gallery instead of a chat stream. Each post is
# a first-class Rooms::Post that belongs directly to the forum, its body the
# post's first message. Like an open room, a forum is a joinable sidebar room —
# but its posts do not ping every member, and joining does not fan a membership
# row out to every post: access derives from forum membership (see viewable_by?)
# and members follow individual posts lazily.
class Rooms::Forum < Room
  include Room::AutoJoinable

  # A forum is always community-wide: every active user is a member and new
  # signups join automatically. auto_join is forced on (and not exposed in the
  # UI), so Room::AutoJoinable adds all users on create.
  before_validation :enable_auto_join

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
  # its Board) — the member check itself lives on the base Room.

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

  # Deleting a forum cuts access instantly but defers the heavy cascade. The
  # forum row and its own memberships deactivate synchronously — so viewable_by?
  # (which its posts delegate to here) fails on the next click and the forum
  # leaves the sidebar — while the O(posts × replies) soft-delete of every post
  # runs in ForumDeactivationJob. A forum owns no messages of its own (posts hold
  # them), so there's nothing else to clean up synchronously.
  def deactivate
    raise CannotDeleteOriginalError if original?

    transaction do
      memberships.update_all(active: false)
      deactivate!
    end

    ForumDeactivationJob.perform_later(forum: self)
  end

  # Mirror of #deactivate: bring the forum back instantly (row + its own
  # memberships) so it reappears in the sidebar and viewable_by? passes on the
  # next click, then restore its cascade-deactivated posts in the background.
  # Only posts the forum's delete cascaded are restored — one deleted on its own
  # stays deleted (R15).
  def reactivate
    transaction do
      memberships.rewhere(active: false).update_all(active: true)
      activate!
    end

    ForumReactivationJob.perform_later(forum: self)
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

  # Silence one member's post follows so reply notifications stop for a forum
  # they left — their per-post memberships go invisible. Scoped to that member,
  # never touches other members. Runs from ForumFollowCleanupJob.
  def silence_post_follows_for(user)
    post_ids = Rooms::Post.where(parent_room_id: id).select(:id)
    Membership.active.where(user_id: user.id, room_id: post_ids)
              .where.not(involvement: "invisible")
              .update_all(involvement: "invisible")
  end

  # Poke the forum's sidebar unread for the members a post's activity should reach
  # (see Message::Threadable#mark_forum_unread). The forum owns no messages, so this
  # mirrors a chat room's unread behavior against the forum's own memberships. It
  # deliberately does NOT bump last_active_at — a post surfaces the forum via its
  # unread state (which sorts to the top of its group), not chat-style reordering.
  def mark_unread_from_post(message)
    # A new post lights the whole forum unread — a dot, like any new room message.
    mark_members_unread(message) if message.room.opening_message?(message)

    # A mention lights the forum unread AND bumps its notification count, so the
    # sidebar shows a number badge, exactly like a chat-room mention.
    notify_mentioned_members(message)
  end

  private
    def enable_auto_join
      self.auto_join = true
    end

    def clean_up_post_follows_later(user)
      ForumFollowCleanupJob.perform_later(forum: self, user: user)
    end

    # Every disconnected member but the author — a member viewing the gallery sees
    # the post live and their presence already keeps them read.
    def mark_members_unread(message)
      recipients = memberships.visible.disconnected.where.not(user_id: message.creator_id)
      recipients.read.update_all(unread_at: message.created_at, updated_at: Time.current)
      recipients.includes(:user).each { |membership| broadcast_dot(membership) }
    end

    # The named members (never the author), while they're away: each gets the dot
    # and +1 on the notification count so the forum shows a number badge.
    def notify_mentioned_members(message)
      mentioned = message.mentionees.reject { |user| user.id == message.creator_id }
      memberships.visible.disconnected.where(user: mentioned).includes(:user).each do |membership|
        membership.update!(
          unread_at: membership.unread_at || message.created_at,
          unread_notifications_count: membership.unread_notifications_count + 1
        )
        broadcast_dot(membership)
        UnreadNotificationsChannel.broadcast_to(membership.user, { roomId: id })
      end
    end

    def broadcast_dot(membership)
      UserUnreadRoomsChannel.broadcast_to(membership.user, {
        roomId: id, roomSize: messages_count, roomUpdatedAt: last_active_at.iso8601, forceUnread: true
      })
    end
end
