# Rooms that start off from a parent message and inherit permissions from that message's room.
class Rooms::Thread < Room
  class NestedThreadError < StandardError; end

  validates_presence_of :parent_message
  # Forum posts are titled; chat threads are not. Guarded on forum_post? so the
  # nameless chat thread stays valid.
  validates :name, presence: true, if: :forum_post?

  # Forum posts are Rooms::Thread instances whose parent message lives in a
  # forum. They carry a title (stored in `name`), a permanent slug, and a Solved
  # state; ordinary chat threads leave all of these unused.
  before_save :assign_forum_post_slug

  # Re-broadcast a post's card + header wherever it renders whenever its title or
  # Solved state changes. Chat threads never touch either column, so this stays
  # dormant for them (broadcast_content_change also guards on forum_post?).
  after_update_commit :broadcast_content_change, if: :content_changed?

  # Gallery filters & sorts, composed by Rooms::Forum#posts.
  scope :solved,                  -> { where.not(solved_at: nil) }
  scope :unsolved,                -> { where(solved_at: nil) }
  scope :recently_active,         -> { order(last_active_at: :desc) }
  scope :reverse_chronologically, -> { order(created_at: :desc) }

  class << self
    def preload_participant_creators(threads, limit: 5)
      threads = threads.to_a.uniq
      return {} if threads.empty?

      ordered_creator_ids_by_thread = grouped_creator_ids_for(threads, limit:)
      users_by_id = User.where(id: ordered_creator_ids_by_thread.values.flatten.uniq)
                        .includes(:badge, avatar_attachment: { blob: :variant_records })
                        .index_by(&:id)

      ordered_creator_ids_by_thread.transform_values do |creator_ids|
        creator_ids.filter_map { |creator_id| users_by_id[creator_id] }
      end
    end

    private
      def grouped_creator_ids_for(threads, limit:)
        thread_ids = threads.map(&:id)
        first_message_times = Message.active.where(room_id: thread_ids)
                                            .group(:room_id, :creator_id)
                                            .minimum(:created_at)

        first_message_times.sort_by { |(thread_id, creator_id), first_message_at| [ thread_id, first_message_at, creator_id ] }
                           .each_with_object(Hash.new { |hash, thread_id| hash[thread_id] = [] }) do |((thread_id, creator_id), _first_message_at), grouped_ids|
          next if grouped_ids[thread_id].size >= limit

          grouped_ids[thread_id] << creator_id
        end
      end
  end

  def self.find_or_create_for(parent_message, users:)
    raise NestedThreadError if parent_message.room.thread?

    parent_message.threads.active.find_by(type: "Rooms::Thread") ||
      create_for({ parent_message_id: parent_message.id }, users: users)
  end

  # Returns users in chronological order (by their first message in the thread)
  def participant_creators(limit: 5)
    ordered_creator_ids = messages.active
      .group(:creator_id)
      .order("MIN(created_at)")
      .limit(limit)
      .pluck(:creator_id)

    return [] if ordered_creator_ids.empty?

    users_by_id = User.where(id: ordered_creator_ids)
      .includes(:badge, avatar_attachment: { blob: :variant_records })
      .index_by(&:id)

    ordered_creator_ids.filter_map { |id| users_by_id[id] }
  end

  def default_involvement(user: nil)
    if user.present? && (user == creator || user == parent_message&.creator)
      "everything"
    else
      "invisible"
    end
  end

  # --- Forum post attributes -------------------------------------------------

  # A forum post's title is stored in the otherwise-unused `name` column.
  def title
    name
  end

  def title=(value)
    self.name = value
  end

  # True when this thread is a forum post (its parent message lives in a forum),
  # as opposed to a chat thread branched off a message in a normal room.
  def forum_post?
    parent_message&.room&.forum?
  end

  def solved?
    solved_at.present?
  end

  # A post is viewable by its members — which, for a forum post, are the forum's
  # members (membership fans out on join). Gates the canonical page.
  def viewable_by?(user)
    user.present? && memberships.active.exists?(user_id: user.id)
  end

  def solve!
    update!(solved_at: Time.current)
  end

  def reopen!
    update!(solved_at: nil)
  end

  # Push a post's current card + header to every surface that renders it (gallery
  # card, panel, standalone page). Called after a Solved change and after a
  # title edit. Streams are keyed by the tenanted forum/post models (never a
  # bare symbol) so updates never leak across workspaces in SaaS. No-op for
  # ordinary chat threads.
  def broadcast_content_change
    return unless forum_post?

    forum = parent_message.room
    broadcast_replace_to [ forum, :posts ],
      target: ActionView::RecordIdentifier.dom_id(self, :card),
      partial: "rooms/forums/post_card",
      locals: { post: self, forum: forum, participants: { id => participant_creators } }
    broadcast_replace_to [ self, :messages ],
      target: ActionView::RecordIdentifier.dom_id(self, :header),
      partial: "rooms/forums/post_header_state",
      locals: { post: self }
  end

  def applicable_activity_types(message)
    types = [ :thread_reply ]
    return types if parent_room&.direct?
    types << :mention if message.mentionees.any?
    types
  end

  # Deactivates the thread. Called either when:
  # 1. An admin deletes this thread directly from the UI
  # 2. The parent room is deactivated (cascades to all its threads)
  # Note: Deleting the parent message does NOT deactivate the thread.
  # `cascade: true` records that this thread was deactivated *because its parent
  # room was* — as opposed to an individual delete. Only cascade-deactivated
  # threads are restored when the parent room is reactivated, so a post deleted
  # on its own stays deleted across a forum delete/restore (R15).
  def deactivate(cascade: false)
    transaction do
      Membership.where(room_id: id).update_all(active: false)
      Message.where(room_id: id).update_all(active: false)
      self.cascade_deactivated = cascade
      deactivate!
    end
  end

  # Thread handles its own reactivation
  def reactivate
    transaction do
      Membership.where(room_id: id, active: false).update_all(active: true)
      Message.where(room_id: id, active: false).update_all(active: true)
      self.cascade_deactivated = false
      activate!
    end
  end

  private
    def content_changed?
      saved_change_to_name? || saved_change_to_solved_at?
    end

    # Generate a permanent, URL-safe slug the first time a forum post is given a
    # title. It is never regenerated on later renames, so shared links stay valid.
    def assign_forum_post_slug
      return unless forum_post? && name.present? && slug.blank?

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
