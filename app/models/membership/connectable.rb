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
    # that knows. "Are they here?" is `connected:` — the refcount plus freshness.
    # "How long ago were they here?" is the preserved last-seen, which is what
    # the away tier reads. Closing a browser goes grey at once because the
    # refcount drops, even though last-seen deliberately survives for email.
    def activity_status(connected_at, connected: true)
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

    def online_user_count(since: ACTIVITY_TIERS[:active])
      where(connected_at: since.ago..).select(:user_id).distinct.count
    end

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

  # Leaving counts everything watched live as seen, so the cursor advances to
  # the room's head — unless the member explicitly marked the room unread, which
  # must survive the disconnect.
  #
  # The advance deliberately does not wait for the refcount to reach zero. The
  # member was watching right up to this moment, so everything so far is seen
  # whether or not another tab is still open — and a tab that is still open
  # advances the cursor on its own heartbeat anyway. Gating it on `connections
  # < 1` would mean a refcount that drifted high (a broker restart fires no
  # depart, so its session's +1 is never undone) silently stops counting watched
  # messages as seen, which is the one harm that wouldn't heal. See OQ4.
  #
  # last-seen is never cleared here: it's what email's away tier reads, and
  # wiping it on disconnect is what made a member look instantly away.
  def disconnected
    decrement_connections
    advance_cursor_to_head unless marked_unread?
  end

  # The heartbeat. It arrives every client cadence from every open tab, so what
  # matters most is how often it writes *nothing*: last-seen only has to stay
  # fresher than CONNECTION_TTL, so re-stamping it on every beat was pure write
  # amplification against a single SQLite writer. Idle watching now costs zero
  # writes; a watcher writes once per CONNECTION_REFRESH_THRESHOLD.
  #
  # The skip is decided here rather than in a WHERE clause on the UPDATE: a
  # statement that matches no rows still opens a write transaction, which is the
  # exact thing being avoided.
  def refresh_connection
    # Never resurrect a departed membership — a refresh can be in flight when
    # the tab closes and land after depart.
    return unless connections > 0
    return if connected_at? && connected_at > CONNECTION_REFRESH_THRESHOLD.ago

    self.class.refresh(self, marked_unread? ? nil : room_head_position)
  end

  # A stale refcount is not worth decrementing down from — whatever it was
  # counting is long gone, so drop straight to zero.
  def decrement_connections
    connected? ? decrement!(:connections, touch: true) : update!(connections: 0)
  end

  private
    def reset_user_connections_if_deactivated
      user.reset_remote_connections if deactivated?
    end

    def reset_user_connections
      user.reset_remote_connections
    end
end
