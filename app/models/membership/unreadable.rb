# Derived unread. A membership stores a (last_read_at, last_read_message_id)
# cursor — the position of the last message its member has seen — and
# unread-ness is derived by comparing that cursor against the room's active
# messages. Sending a message writes nothing to member rows (the sender's own
# cursor aside), and a soft-deleted message stops counting automatically
# because the comparison only sees active messages.
#
# The cursor advances at view-time: when the membership is created, when the
# member presents in the room, on presence refresh, and when they fully
# disconnect (messages watched live count as seen). The cutover migration
# reset every member to caught-up; a membership with no cursor (created in
# the deploy window by pre-cursor code) reads as read, not all-unread.
#
# marked_unread covers the one state a cursor cannot: an explicit
# mark-as-unread, which must survive connection churn without being wiped by
# a cursor advance. (A forum owns no messages, but its dot still derives —
# from posts created after the cursor. See UNSEEN_POSTS_SQL.)
module Membership::Unreadable
  extend ActiveSupport::Concern

  # A membership has unseen messages when an active message in its room sits
  # strictly after its cursor. Correlated form, for scopes over memberships.
  UNSEEN_MESSAGES_SQL = <<~SQL.squish
    EXISTS (
      SELECT 1 FROM messages
      WHERE messages.room_id = memberships.room_id
        AND messages.active = TRUE
        AND (messages.created_at > memberships.last_read_at
          OR (messages.created_at = memberships.last_read_at AND messages.id > memberships.last_read_message_id))
    )
  SQL

  # A forum owns no messages: its dot derives from active posts (sub-rooms)
  # created after the cursor instead. Time-only comparison — the cursor's
  # message id means nothing against posts. Rides
  # index_rooms_on_parent_room_and_created.
  UNSEEN_POSTS_SQL = <<~SQL.squish
    EXISTS (
      SELECT 1 FROM rooms posts
      WHERE posts.parent_room_id = memberships.room_id
        AND posts.type = 'Rooms::Post'
        AND posts.active = TRUE
        AND posts.created_at > memberships.last_read_at
    )
  SQL

  UNSEEN_SQL = "(#{UNSEEN_MESSAGES_SQL} OR #{UNSEEN_POSTS_SQL})"

  included do
    has_many :unread_notifications, ->(membership) {
      scope = if membership.last_read_at
        after_cursor(membership.last_read_at, membership.last_read_message_id)
      else
        none
      end

      if membership.room.direct?
        scope
      else
        scope.where(
          "EXISTS (SELECT 1 FROM notifications WHERE notifications.message_id = messages.id
            AND notifications.user_id = ? AND notifications.activity_type = 'mention')
           OR messages.mentions_everyone = ?",
          membership.user_id, true
        ).distinct
      end
    }, through: :room, source: :messages

    scope :read, -> {
      where(marked_unread: false)
        .where("(#{Membership::Connectable::CONNECTED_SQL}) OR memberships.last_read_at IS NULL OR NOT #{UNSEEN_SQL}",
               connection_ttl: Membership::Connectable::CONNECTION_TTL.ago)
    }
    scope :unread, -> {
      visible.merge(
        where(marked_unread: true).or(
          where(Membership::Connectable::DISCONNECTED_SQL, connection_ttl: Membership::Connectable::CONNECTION_TTL.ago)
            .where.not(last_read_at: nil)
            .where(UNSEEN_SQL)
        )
      )
    }
    # Memberships that have unread messages OR whose room was updated recently.
    # Used to filter direct messages in the sidebar to only show recent conversations.
    scope :recently_active_or_unread, ->(since: 7.days.ago) {
      joins(:room).where(
        "memberships.marked_unread = TRUE OR (memberships.last_read_at IS NOT NULL AND #{UNSEEN_SQL}) OR rooms.updated_at > :since",
        since: since
      )
    }
    # Memberships for whom the given message is unseen: their cursor sits
    # before it and they weren't watching live (connected members see the
    # message as it lands; an explicit mark-as-unread counts as not watching).
    # This is the eligibility test for unread_notifications_count bumps and
    # their reversals.
    scope :with_message_unseen, ->(created_at, id) {
      where("memberships.last_read_at IS NOT NULL AND (memberships.last_read_at < :t OR (memberships.last_read_at = :t AND memberships.last_read_message_id < :id))",
            t: created_at, id: id)
        .merge(
          where(marked_unread: true)
            .or(where(Membership::Connectable::DISCONNECTED_SQL, connection_ttl: Membership::Connectable::CONNECTION_TTL.ago))
        )
    }
    # Memberships caught up on everything except, at most, the given message —
    # no explicit mark, nothing else unseen. The set whose cursor may safely
    # advance past that message.
    scope :caught_up_besides, ->(message) {
      where(marked_unread: false).where(<<~SQL.squish, message_id: message.id)
        NOT EXISTS (
          SELECT 1 FROM messages
          WHERE messages.room_id = memberships.room_id
            AND messages.active = TRUE
            AND messages.id != :message_id
            AND (memberships.last_read_at IS NULL
              OR messages.created_at > memberships.last_read_at
              OR (messages.created_at = memberships.last_read_at AND messages.id > memberships.last_read_message_id))
        )
      SQL
    }
    # The forum analog of caught_up_besides: caught up on every post except,
    # at most, the given one. The set whose cursor may safely advance past
    # that post.
    scope :caught_up_besides_post, ->(post) {
      where(marked_unread: false).where(<<~SQL.squish, post_id: post.id)
        NOT EXISTS (
          SELECT 1 FROM rooms posts
          WHERE posts.parent_room_id = memberships.room_id
            AND posts.type = 'Rooms::Post'
            AND posts.active = TRUE
            AND posts.id != :post_id
            AND (memberships.last_read_at IS NULL
              OR posts.created_at > memberships.last_read_at)
        )
      SQL
    }

    before_create :snapshot_read_cursor
  end

  def read?
    !unread?
  end

  def unread?
    return false if involved_in_invisible?
    return true if marked_unread?
    return false if connected?
    unseen_messages? || unseen_posts?
  end

  def read
    head_at, head_id = room_head_position
    update!(last_read_at: head_at, last_read_message_id: head_id, marked_unread: false, unread_notifications_count: 0)
    broadcast_read
    Desktop::BadgeState.broadcast_to(user)
  end

  def mark_unread_at(message)
    cursor_at, cursor_id = position_before(message)
    update!(
      last_read_at: cursor_at, last_read_message_id: cursor_id, marked_unread: true,
      unread_notifications_count: count_unseen_notifications(cursor_at, cursor_id)
    )
    broadcast_unread
    Desktop::BadgeState.broadcast_to(user)
  end

  def read_until(time)
    return if read?

    next_unread = room.messages.without_events.ordered.where("created_at > ?", time).first
    if next_unread.nil?
      read
    else
      cursor_at, cursor_id = position_before(next_unread)
      return if cursor_at_or_after?(cursor_at, cursor_id)

      update!(
        last_read_at: cursor_at, last_read_message_id: cursor_id, marked_unread: false,
        unread_notifications_count: count_unseen_notifications(cursor_at, cursor_id)
      )
    end
  end

  # Marks the room unread from its latest message without recomputing the
  # badge or broadcasting — the quiet involve-with-unread path.
  def rewind_to_unread
    last = room.messages.reorder(:created_at, :id).last
    cursor_at, cursor_id = last ? position_before(last) : [ Time.at(0), 0 ]
    update!(last_read_at: cursor_at, last_read_message_id: cursor_id, marked_unread: true)
  end

  def clear_unread_notifications_until(time)
    update!(unread_notifications_count: count_unread_notifications_after(time))
  end

  def has_unread_notifications?
    unread_notifications_count > 0
  end

  # When this membership became unread: the first unseen message's timestamp.
  # Nil when read, or when the unread carries no message (a forum's
  # post-derived dot, or an explicit mark in an empty room).
  def unread_since
    return nil unless unread?
    first_unread_message&.created_at
  end

  def first_unread_message
    return nil if last_read_at.nil?
    room.messages.after_cursor(last_read_at, last_read_message_id).order(:created_at, :id).first
  end

  def unseen_messages?
    return false if last_read_at.nil?
    room.messages.after_cursor(last_read_at, last_read_message_id).exists?
  end

  # The forum arm of unread?: active posts created after the cursor.
  def unseen_posts?
    return false if last_read_at.nil? || !room.forum?
    room.posts.where("created_at > ?", last_read_at).exists?
  end

  # Recompute the count of notification-worthy messages after a cursor
  # position. Returns 0 for a nil cursor (membership reads as read).
  def count_unseen_notifications(from_at = last_read_at, from_id = last_read_message_id)
    return 0 if from_at.nil?

    base = room.messages.after_cursor(from_at, from_id)

    if room.direct?
      base.count
    else
      base.where(
        "messages.mentions_everyone = ? OR EXISTS (" \
          "SELECT 1 FROM notifications WHERE notifications.message_id = messages.id " \
          "AND notifications.user_id = ? AND notifications.activity_type = 'mention')",
        true, user_id
      ).count
    end
  end

  # Advances the cursor to the room's newest message — the member has seen
  # everything up to now. Skips callbacks: pure bookkeeping.
  def advance_cursor_to_head
    head_at, head_id = room_head_position
    update_columns(last_read_at: head_at, last_read_message_id: head_id, updated_at: Time.current)
  end

  # The room's newest active message position, or a caught-up-as-of-now
  # sentinel for a room with no messages (never nil: a nil cursor reads as
  # read and would silence future dots).
  def room_head_position
    head = room.messages.reorder(:created_at, :id).last
    head ? [ head.created_at, head.id ] : [ Time.current, 0 ]
  end

  private
    def snapshot_read_cursor
      return if last_read_at.present?
      self.last_read_at, self.last_read_message_id = room_head_position if room
    end

    def position_before(message)
      previous = room.messages.before_cursor(message.created_at, message.id)
                     .reorder(created_at: :desc, id: :desc).first
      previous ? [ previous.created_at, previous.id ] : [ Time.at(0), 0 ]
    end

    def cursor_at_or_after?(time, id)
      last_read_at.present? &&
        (last_read_at > time || (last_read_at == time && last_read_message_id >= id))
    end

    def count_unread_notifications_after(time)
      return 0 if last_read_at.nil? || read?

      Notification.joins(:message)
        .where(user_id: user_id, activity_type: "mention", messages: { room_id: room_id })
        .merge(Message.after_cursor(last_read_at, last_read_message_id))
        .where("notifications.created_at > ?", time)
        .count
    end

    # Read-state transitions are per-user, so both directions ride the
    # member's own ReadRoomsChannel: a bare { room_id: } means read; the
    # mark-as-unread form adds unread: true plus the sidebar sort keys.
    def broadcast_read
      ReadRoomsChannel.broadcast_to(user, { room_id: room_id })
    end

    def broadcast_unread
      ReadRoomsChannel.broadcast_to(user, unread_payload)
      UnreadNotificationsChannel.broadcast_to(user, notification_payload) if has_unread_notifications?
    end

    def unread_payload
      {
        room_id: room.id,
        room_size: room.messages_count,
        room_updated_at: room.last_active_at.iso8601,
        unread: true
      }
    end

    def notification_payload
      { roomId: room.id }
    end
end
