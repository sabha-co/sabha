# A chat thread: a room that starts off from a parent message and inherits
# permissions from that message's room. (Forum posts are Rooms::Post, not
# threads — their title, slug, Solved state, and gallery live there.)
class Rooms::Thread < Room
  class NestedThreadError < StandardError; end
  class BlankReplyError < StandardError; end

  include Room::Participants, Room::Nested, Room::Followable

  validates_presence_of :parent_message

  # Denormalize the room this thread was spawned in (see Room#parent_room).
  before_validation :assign_parent_room, on: :create

  # A provisional reply panel (Rooms::ThreadsController#new) has no thread to
  # stream from, so a second one left open goes stale once someone else's reply
  # materializes the thread. Reload those open panels into the real thread.
  after_create_commit :supersede_provisional_panels

  # Access derives from the room this thread was spawned in — a member of the
  # parent room can open the thread without a per-thread membership row (mirrors
  # Rooms::Post delegating to its forum).
  delegate :viewable_by?, to: :parent_room

  # @mentions resolve against the parent room's roster rather than the thread's
  # handful of followers, so a parent member can be mentioned in before they've
  # engaged (mirrors Rooms::Post#mentionable_users).
  def mentionable_users
    parent_room.users
  end

  # Grants a membership to the thread creator and the parent-message author only
  # — a thread never fans a row out to every parent-room member. Both auto-follow
  # (involvement "everything" via #default_involvement) so replies notify them:
  # the author hears about a thread opened on their message even when someone else
  # opens it. The author is included only while they can still reach the parent
  # room, so an author who has left isn't notified into a thread they can no longer
  # open. Every other member views via derived access (see #viewable_by?) and
  # follows lazily on their first reply.
  def self.find_or_create_for(parent_message, creator:)
    raise NestedThreadError if parent_message.room.thread?

    parent_message.threads.active.find_by(type: "Rooms::Thread") ||
      create_for_parent(parent_message, creator)
  end

  # The create branch of find_or_create_for, isolated in a savepoint (requires_new)
  # so a lost race on the unique parent_message_id index rolls back only this
  # attempt. Without the savepoint, create_for's transaction would join an
  # enclosing one (reply_to's) and — on PostgreSQL — the failed INSERT would abort
  # that whole transaction, so the recovering find_by! would raise
  # InFailedSqlTransaction instead of returning the row the winner created.
  def self.create_for_parent(parent_message, creator)
    transaction(requires_new: true) do
      create_for({ parent_message_id: parent_message.id, creator: creator },
                 users: auto_followers(parent_message, creator))
    end
  rescue ActiveRecord::RecordNotUnique
    parent_message.threads.active.find_by!(type: "Rooms::Thread")
  end
  private_class_method :create_for_parent

  # Materializes the thread lazily, on its first reply, and returns that reply: a
  # thread only exists once someone actually replies, so opening the panel writes
  # nothing (see Rooms::ThreadsController#new). Both live in one transaction so a
  # blank first reply rolls back a *just-created* thread rather than leaving an
  # empty room behind — while a thread that already existed (committed earlier) is
  # left intact, we simply don't add the invalid reply to it.
  def self.reply_to(parent_message, creator:, message_params:)
    transaction do
      thread = find_or_create_for(parent_message, creator: creator)
      reply = thread.messages.create_with_attachment!(message_params.merge(creator: creator))

      # Messages carry no body-presence validation, so a blank body with no
      # attachment would otherwise leave an empty thread behind — the exact thing
      # lazy materialization exists to prevent. Roll the just-opened thread back.
      raise BlankReplyError if reply.plain_text_body.blank?

      reply
    end
  end

  # The thread creator always follows; the parent-message author auto-follows too,
  # but only while they're still a *visible* member of the parent room. An active-
  # row check (viewable_by?) isn't enough: self-service leave keeps the membership
  # active and only flips involvement to "invisible", so viewable_by? still passes
  # — yet a member who left shouldn't be pulled into, and notified about, a new
  # thread opened on their old message.
  def self.auto_followers(parent_message, creator)
    followers = [ creator ]
    author = parent_message.creator
    followers << author if parent_message.room.memberships.active.visible.exists?(user_id: author.id)
    followers.uniq
  end
  private_class_method :auto_followers

  # The involvement a membership is granted at, not a claim that these users are
  # always followed: the creator always is, but the parent-message author only
  # gets a row while they can still reach the parent room (see .auto_followers).
  def default_involvement(user: nil)
    if user.present? && (user == creator || user == parent_message&.creator)
      "everything"
    else
      "invisible"
    end
  end

  def applicable_activity_types(message)
    types = [ :thread_reply ]
    return types if parent_room&.direct?
    types << :mention if message.mentionees.any?
    types
  end

  private
    def assign_parent_room
      self.parent_room_id ||= parent_message&.room_id
    end

    # Broadcast to every open provisional panel for this parent message (they
    # subscribe to [parent_message, :thread]) a lazy frame that reloads the real
    # thread. A panel that already navigated to the thread no longer carries this
    # subscription, so the reply author's own panel isn't disturbed.
    def supersede_provisional_panels
      broadcast_replace_to [ parent_message, :thread ],
        target: "thread_panel_frame",
        partial: "rooms/threads/superseding_panel",
        locals: { thread: self }
    end
end
