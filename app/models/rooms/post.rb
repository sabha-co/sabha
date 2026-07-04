# A first-class forum post: a room that belongs directly to its forum, whose
# opening body is simply its first message and whose replies are the messages
# that follow. Sibling of Rooms::Thread (a chat thread branched off a message) —
# both list participants the same way (Room::Participants), but a post carries a
# title, a permanent slug, a Solved state, and derives its access from the forum
# rather than from a per-member membership fan-out.
class Rooms::Post < Room
  include Room::Participants, Room::Nested

  # The forum this post lives in. The real FK (rooms.parent_room_id), unlike a
  # chat thread's denormalized copy of its parent message's room.
  belongs_to :parent_room, class_name: "Rooms::Forum"

  # Solved is a record (see Solution), not a rooms column: present iff solved.
  has_one :solution, foreign_key: :post_id, dependent: :destroy

  validates :name, presence: true

  before_save :assign_slug

  # Stream a new post into the top of every member's open gallery. The author
  # sees it via their post-create redirect; this reaches everyone else watching.
  after_create_commit :broadcast_gallery_insertion

  # Re-broadcast the post's card + header when its title changes. Solved changes
  # go through solve!/reopen! (which create/destroy a Solution — no rooms update
  # fires here), so they broadcast explicitly.
  after_update_commit :broadcast_content_change, if: :content_changed?

  # Gallery filters & sorts, composed by Rooms::Forum#posts.
  scope :solved,                  -> { joins(:solution) }
  scope :unsolved,                -> { where.missing(:solution) }
  scope :recently_active,         -> { order(last_active_at: :desc) }
  scope :reverse_chronologically, -> { order(created_at: :desc) }

  # Replies exclude the opening message (message #1), which carries the post
  # body. messages_count counts every message in the room, so subtract the OP.
  def replies_count
    [ messages_count - 1, 0 ].max
  end

  # The id of the opening message (message #1) — the post body, its earliest
  # message. The single definition of "which message opens the post"; the message
  # list helper (forum_opening_message?) reads it too.
  def opening_message_id
    messages.active.order(:created_at, :id).pick(:id)
  end

  # The opening message can't be deleted on its own (that would leave a bodyless
  # post); delete the whole post instead.
  def opening_message?(message)
    message.id == opening_message_id
  end

  # A post's title is stored in the `name` column.
  def title
    name
  end

  def title=(value)
    self.name = value
  end

  def solved?
    solution.present?
  end

  # Derived from the Solution record so views calling post.solved_at / solved_by
  # keep working after the column was dropped.
  def solved_at
    solution&.created_at
  end

  def solved_by
    solution&.user
  end

  def solve!
    return if solved?

    create_solution!
    broadcast_content_change
  end

  def reopen!
    return unless solved?

    solution.destroy!
    association(:solution).reset
    broadcast_content_change
  end

  # Access is defined once on the forum and delegated down, Fizzy-style — a post
  # has no per-member membership row of its own for every forum member.
  delegate :viewable_by?, to: :parent_room

  def default_involvement(user: nil)
    user.present? && user == creator ? "everything" : "invisible"
  end

  # True when the user is a follower — an active, non-invisible membership that
  # drives reply notifications. The author and anyone who replied or explicitly
  # Followed qualifies; a member who never engaged (access is forum-derived) does
  # not.
  def followed_by?(user)
    user.present? && memberships.active.where.not(involvement: "invisible").exists?(user_id: user.id)
  end

  # A member becomes a follower of this post the moment they reply — lazily, so
  # a forum never fans a membership row out to every member. Idempotent and
  # self-healing: it (re)activates a dropped membership and lifts an invisible
  # one back to "everything", but never downgrades a follower who dialed
  # themselves down. Mirrors Fizzy's Watch created on comment.
  def follow!(user)
    membership = Membership.find_or_initialize_by(room_id: id, user_id: user.id)
    membership.active = true
    membership.involvement = "everything" if membership.new_record? || membership.involved_in_invisible?
    membership.save! if membership.changed?
    membership
  end

  def unfollow!(user)
    Membership.where(room_id: id, user_id: user.id).destroy_all
  end

  def applicable_activity_types(message)
    types = [ :thread_reply ]
    types << :mention if message.mentionees.any?
    types
  end

  # Prepend this post's card into the forum gallery for every member watching it
  # live — a brand-new card has no element to replace yet, so insertion needs its
  # own action. Newest-first is the top for both gallery sorts (recent activity /
  # newest), so the head of the list is always the right slot.
  #
  # Two accepted, self-correcting limitations: a viewer filtering to "Solved"
  # briefly sees the new (unsolved) post, and a viewer sitting on the empty-state
  # gallery (no list container yet) sees nothing until they navigate — the forum
  # stream is neither filter- nor emptiness-aware. Both resolve on next load,
  # short of fanning a stream out per filter.
  def broadcast_gallery_insertion
    broadcast_prepend_to [ parent_room, :posts ],
      target: ActionView::RecordIdentifier.dom_id(parent_room, :posts),
      partial: "rooms/forums/post_card",
      locals: { post: self, forum: parent_room, participants: { id => participant_creators } }
  end

  # Replace this post's gallery card wherever it renders — reply count, activity,
  # participant avatars, title, Solved badge. Fired both by a new reply
  # (Message::Threadable#update_forum_gallery_card) and by a title/Solved change
  # here. Keyed by the tenanted forum model (never a bare symbol) so updates
  # never leak across workspaces in SaaS.
  def broadcast_gallery_card
    broadcast_replace_to [ parent_room, :posts ],
      target: ActionView::RecordIdentifier.dom_id(self, :card),
      partial: "rooms/forums/post_card",
      locals: { post: self, forum: parent_room, participants: { id => participant_creators } }
  end

  # Push the post's current card + header to every surface that renders it
  # (gallery card, panel, standalone page). Called after a Solved change and
  # after a title edit.
  def broadcast_content_change
    broadcast_gallery_card
    broadcast_replace_to [ self, :messages ],
      target: ActionView::RecordIdentifier.dom_id(self, :header),
      partial: "rooms/forums/post_header_state",
      locals: { post: self }
  end

  private
    def content_changed?
      saved_change_to_name?
    end

    # Generate a permanent, URL-safe slug the first time the post is titled. It
    # is never regenerated on a later rename, so shared links stay valid.
    def assign_slug
      return unless name.present? && slug.blank?

      self.slug = unique_slug_from_title
    end

    def unique_slug_from_title
      base = name.parameterize.presence || "post"
      candidate = base
      suffix = 2
      # The rooms.slug unique index is the hard guarantee; this loop just avoids
      # the common collision. Concurrent creates of the same title can still race
      # the index — the loser retries in Rooms::Forum#post!.
      while Room.where.not(id: id).exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      candidate
    end
end
