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

  # The thread-room ids the reader follows, across the whole page — one query so
  # the cards can render the follow control without a per-card `followed_by?`.
  # Follower semantics match Room::Followable#followed_by?: an active,
  # non-invisible membership on the thread room.
  def self.followed_thread_room_ids(user, messages)
    thread_room_ids = messages.flat_map { |m| m.threads.select(&:active?).map(&:id) }
    return Set.new if thread_room_ids.empty?

    Membership.active
              .where.not(involvement: "invisible")
              .where(room_id: thread_room_ids, user_id: user.id)
              .pluck(:room_id)
              .to_set
  end

  def initialize(user)
    @user = user
  end

  def call
    accessible_thread_parents
      .for_display
      .includes(threads: :creator)
      .order(thread_activity_order)
  end

  # The total accessible-thread count for the header badge. Runs the same
  # accessible-parents subquery as #call, but without for_display's eager-load
  # tree or the activity ordering — neither affects a COUNT.
  def count
    accessible_thread_parents.count
  end

  private

  def accessible_thread_parents
    Message.active
           .without_events
           .joins(:room)
           .where.not(rooms: { type: "Rooms::Thread" })
           .where("messages.id IN (#{accessible_thread_parent_ids_sql})")
  end

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
