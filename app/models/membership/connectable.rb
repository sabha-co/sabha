module Membership::Connectable
  extend ActiveSupport::Concern

  # How stale a watching member's last-seen may get before we stop believing
  # they're there. It bounds a silent transport death — a dead socket fires no
  # depart, so this timestamp going cold is the only tell. It must exceed
  # CONNECTION_REFRESH_THRESHOLD (a live watcher only rewrites the column that
  # often) or watchers would flicker offline between their own heartbeats.
  CONNECTION_TTL = 5.minutes

  # Only rewrite last-seen once it's this stale. The heartbeat still arrives
  # every client cadence; nearly all of them now write nothing.
  CONNECTION_REFRESH_THRESHOLD = 4.minutes

  # "Watching this room right now", in SQL. Both halves carry weight: the
  # refcount drops the instant a member leaves, while the timestamp is what
  # catches a socket that died without saying so.
  CONNECTED_SQL = "memberships.connections > 0 AND memberships.connected_at >= :connection_ttl"
  DISCONNECTED_SQL = "(memberships.connections < 1 OR memberships.connected_at IS NULL OR memberships.connected_at < :connection_ttl)"

  included do
    scope :connected,    -> { where(CONNECTED_SQL, connection_ttl: CONNECTION_TTL.ago) }
    scope :disconnected, -> { where(DISCONNECTED_SQL, connection_ttl: CONNECTION_TTL.ago) }

    after_update_commit  :reset_user_connections_if_deactivated
    after_destroy_commit :reset_user_connections
  end

  ACTIVITY_TIERS = { active: 10.minutes, away: 1.hour, recently_active: 24.hours }.freeze

  class_methods do
    # One UPDATE. Re-stamping last-seen and carrying the read cursor forward are
    # the heartbeat's whole job, so they're written together or not at all — two
    # statements would take the writer twice per watcher.
    def refresh(membership, head)
      attributes = { connected_at: Time.current, updated_at: Time.current }
      attributes[:last_read_at], attributes[:last_read_message_id] = head if head

      where(id: membership.id).update_all(attributes)
    end

    def connect(membership, connections)
      head_at, head_id = membership.room_head_position
      where(id: membership.id).update_all(
        connections: connections, connected_at: Time.current,
        last_read_at: head_at, last_read_message_id: head_id,
        marked_unread: false, unread_notifications_count: 0,
        updated_at: Time.current
      )
    end

    def last_connected_at_for(user_ids)
      where(user_id: user_ids).group(:user_id).maximum(:connected_at)
    end

    # A dot answers two questions with one word, and each half reads the signal
    # that knows: "are they here" is the refcount plus freshness, "how long ago"
    # is the preserved last-seen. Required rather than defaulted — a default
    # would quietly assume the flattering answer and leave a green dot burning
    # after someone closed their browser.
    def activity_status(connected_at, connected:)
      return :offline unless connected_at
      return :offline unless connected

      if connected_at >= ACTIVITY_TIERS[:active].ago
        :active
      elsif connected_at >= ACTIVITY_TIERS[:away].ago
        :away
      else
        :offline
      end
    end

    def activity_statuses_for(user_ids)
      connected_user_ids = connected.where(user_id: user_ids).distinct.pluck(:user_id).to_set

      last_connected_at_for(user_ids).to_h do |user_id, last_seen|
        [ user_id, activity_status(last_seen, connected: connected_user_ids.include?(user_id)) ]
      end
    end

    # "Here now" — the workspace-vitality count in the header. Pure connection
    # freshness: how many distinct members hold a fresh socket within the tier,
    # with no regard for availability. It answers "how alive is this workspace
    # right now", not "who's free to talk" — so a Do Not Disturb member is
    # counted here while showing a red dot. That's intentional, not a bug; the
    # two answer different questions (see here_now_label for the tooltip that
    # keeps the number from reading as a contradiction, and the User::Presence
    # dot for the availability signal).
    # "Here now" — workspace vitality, connection freshness rather than intent, so
    # a Do Not Disturb member is still counted here while showing a red dot. The
    # one exception is invisible: its whole purpose is to remove you from presence
    # signals, so a hidden member is subtracted from the number too, exactly as
    # they're subtracted from the dots.
    def online_user_count(since: ACTIVITY_TIERS[:active])
      joins(:user)
        .where(connected_at: since.ago..)
        .merge(User.where.not(availability: :invisible))
        .distinct.count(:user_id)
    end

    # Is this member reachable within the active tier — pure connection, no
    # availability. accounts_helper reads it to avoid adding the current viewer to
    # the count twice; the invisible case is handled there, not here.
    def online?(user, since: ACTIVITY_TIERS[:active])
      where(user_id: user.id, connected_at: since.ago..).exists?
    end

    # Email-only presence check: a user is away when no membership in this
    # tenant has been connected within the away tier (1 hour). Reads last-seen,
    # not connectedness — email asks "has the user been gone long enough that an
    # email is the right way to reach them?", which is why `disconnected` must
    # leave the timestamp alone.
    def workspace_locally_away?(user_id)
      last_seen = last_connected_at_for([ user_id ])[user_id]
      return true if last_seen.nil?
      last_seen < ACTIVITY_TIERS[:away].ago
    end
  end

  def connected?
    connections > 0 && connected_at? && connected_at >= CONNECTION_TTL.ago
  end

  def present
    self.class.connect(self, connected? ? connections + 1 : 1)
  end

  # Leaving counts everything watched live as seen, so the cursor advances —
  # unless the member explicitly marked the room unread, which must survive.
  #
  # The advance deliberately doesn't wait for the refcount to reach zero. A
  # refcount drifts high whenever a session dies without departing (a broker
  # restart), and gating on `connections < 1` would then silently stop counting
  # watched messages as seen. Advancing every time is right anyway: they were
  # watching until this moment, and a tab still open re-advances on its own beat.
  #
  # last-seen is never cleared: it's what email's away tier reads, and wiping it
  # is what made a member look instantly away.
  def disconnect
    decrement_connections
    advance_cursor_to_head unless marked_unread?
  end

  # The heartbeat, which arrives from every open tab on every client cadence.
  # What matters is how often it writes nothing: last-seen only has to stay
  # fresher than CONNECTION_TTL, so re-stamping it every beat was pure write
  # amplification against a single writer.
  #
  # The skip is decided here rather than as a WHERE clause, because an UPDATE
  # matching no rows still opens a write transaction — the thing being avoided.
  def refresh_connection
    return unless connections > 0 # a refresh can land after depart; don't resurrect
    return if connected_at? && connected_at > CONNECTION_REFRESH_THRESHOLD.ago

    self.class.refresh(self, marked_unread? ? nil : room_head_position)
  end

  private
    # A stale refcount isn't worth counting down from — whatever it counted is
    # long gone, so drop straight to zero.
    def decrement_connections
      connected? ? decrement!(:connections, touch: true) : update!(connections: 0)
    end

    def reset_user_connections_if_deactivated
      user.reset_remote_connections if deactivated?
    end

    def reset_user_connections
      user.reset_remote_connections
    end
end
