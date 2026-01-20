# Fetches parent messages with active threads the user can access, ordered by most recent thread activity.
class Inbox::ThreadsQuery
  def initialize(user)
    @user = user
  end

  def call
    Message.active
           .joins(:room)
           .where.not(rooms: { type: "Rooms::Thread" })
           .where(id: accessible_thread_parent_ids)
           .with_threads
           .with_creator
           .order(thread_activity_order)
  end

  private

  attr_reader :user

  def accessible_thread_parent_ids
    Room.active
        .where(id: all_accessible_thread_ids, type: "Rooms::Thread")
        .where("messages_count > 0")
        .pluck(:parent_message_id)
  end

  # Combines explicit thread memberships with implicit access via parent room "everything" involvement
  def all_accessible_thread_ids
    thread_ids_from_memberships | thread_ids_from_parent_rooms
  end

  def thread_ids_from_memberships
    user.memberships.active.visible
        .joins(:room)
        .where(rooms: { type: "Rooms::Thread" })
        .pluck(:room_id)
  end

  def thread_ids_from_parent_rooms
    Room.where(type: "Rooms::Thread")
        .joins(:parent_message)
        .where(messages: { room_id: parent_room_ids_with_everything_involvement })
        .pluck(:id)
  end

  def parent_room_ids_with_everything_involvement
    user.memberships.active.involved_in_everything
        .joins(:room)
        .where.not(rooms: { type: "Rooms::Thread" })
        .pluck(:room_id)
  end

  def thread_activity_order
    Arel.sql(<<~SQL)
      (SELECT threads.last_active_at
       FROM rooms threads
       WHERE threads.parent_message_id = messages.id
       AND threads.type = 'Rooms::Thread'
       LIMIT 1)
    SQL
  end
end
