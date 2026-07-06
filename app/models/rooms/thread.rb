# A chat thread: a room that starts off from a parent message and inherits
# permissions from that message's room. (Forum posts are Rooms::Post, not
# threads — their title, slug, Solved state, and gallery live there.)
class Rooms::Thread < Room
  class NestedThreadError < StandardError; end

  include Room::Participants, Room::Nested

  validates_presence_of :parent_message

  # Denormalize the room this thread was spawned in (see Room#parent_room).
  before_validation :assign_parent_room, on: :create

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
      create_for({ parent_message_id: parent_message.id, creator: creator },
                 users: auto_followers(parent_message, creator))
  end

  # The thread creator always follows; the parent-message author auto-follows too,
  # but only while they can still reach the parent room — access is parent-derived,
  # so auto-following an author who has left would notify them into a thread they
  # could no longer open.
  def self.auto_followers(parent_message, creator)
    followers = [ creator ]
    followers << parent_message.creator if parent_message.room.viewable_by?(parent_message.creator)
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
end
