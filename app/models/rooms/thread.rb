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

  # Grants a membership to the creator only — a thread never fans a row out to
  # every parent-room member. Other members view via derived access (see
  # #viewable_by?) and follow lazily on their first reply.
  def self.find_or_create_for(parent_message, creator:)
    raise NestedThreadError if parent_message.room.thread?

    parent_message.threads.active.find_by(type: "Rooms::Thread") ||
      create_for({ parent_message_id: parent_message.id, creator: creator }, users: [ creator ])
  end

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
