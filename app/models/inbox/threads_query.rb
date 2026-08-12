# Fetches parent messages with active threads the user can access, ordered by most recent thread activity.
class Inbox::ThreadsQuery
  # Unseen active-reply counts, per thread room, for the reader — one query so
  # the cards can badge "N new" without an N+1 over the page. Only threads the
  # reader follows (has an active membership on) contribute; the rest carry no
  # badge. A nil cursor reads as caught up, matching Membership::Unreadable.
  def self.unseen_reply_counts(user, messages)
    thread_room_ids = messages.flat_map { |m| m.threads.select(&:active?).map(&:id) }
    return {} if thread_room_ids.empty?

    Message.active.without_events
           .joins("INNER JOIN memberships ON memberships.room_id = messages.room_id")
           .where(room_id: thread_room_ids)
           .where("memberships.user_id = ? AND memberships.active = TRUE", user.id)
           .where("messages.created_at > memberships.last_read_at OR (messages.created_at = memberships.last_read_at AND messages.id > memberships.last_read_message_id)")
           .group("messages.room_id")
           .count
  end

  def initialize(user)
    @user = user
  end

  def call
    Message.active
           .without_events
           .joins(:room)
           .where.not(rooms: { type: "Rooms::Thread" })
           .where("messages.id IN (#{accessible_thread_parent_ids_sql})")
           .for_display
           .order(thread_activity_order)
  end

  private

  attr_reader :user

  # Single SQL subquery that finds all accessible thread parent_message_ids.
  # A thread is accessible if either:
  # 1. User has a direct membership in the thread (visible, not invisible)
  # 2. User has "everything" involvement in the parent room (implicit thread access)
  def accessible_thread_parent_ids_sql
    ApplicationRecord.sanitize_sql_array([ <<~SQL.squish, user.id, user.id ])
      SELECT DISTINCT threads.parent_message_id
      FROM rooms threads
      WHERE threads.active = TRUE
        AND threads.type = 'Rooms::Thread'
        AND threads.messages_count > 0
        AND (
          EXISTS (
            SELECT 1 FROM memberships
            WHERE memberships.room_id = threads.id
              AND memberships.user_id = ?
              AND memberships.active = TRUE
              AND memberships.involvement != 'invisible'
          )
          OR EXISTS (
            SELECT 1 FROM messages
            INNER JOIN memberships ON memberships.room_id = messages.room_id
            WHERE messages.id = threads.parent_message_id
              AND memberships.user_id = ?
              AND memberships.active = TRUE
              AND memberships.involvement = 'everything'
          )
        )
    SQL
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
