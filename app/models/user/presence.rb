module User::Presence
  extend ActiveSupport::Concern

  # How long after the last reported interaction we still call someone active.
  # Borrowed from the socket tracker's "active" tier so the two signals agree on
  # what "recently" means, even though they measure different things: that one
  # watches a heartbeat (is a tab open), this one watches a human (is anyone
  # touching it).
  ACTIVE_WINDOW = Membership::Connectable::ACTIVITY_TIERS[:active]

  # Only rewrite last-active once it's this stale. A busy tab reports on its own
  # cadence; nearly all of those reports write nothing, which is the point —
  # every write here lands on the same single SQLite writer the chat itself uses.
  #
  # It only has to stay fresh enough to answer a ten-minute question, so this is
  # the dial to turn if the writer ever feels it. Reports arrive every two
  # minutes and are dropped unless the watermark is already this old, which puts
  # a real write roughly every four; the cost of a longer interval is only that
  # idleness is noticed a little later, never that it's missed.
  ACTIVITY_REFRESH_THRESHOLD = 3.minutes

  included do
    # NOTE: this attribute shadows ActiveSupport's Object#presence on User
    # instances — `user.presence` is the enum, not the present?-or-nil idiom.
    # Nothing calls it that way today; reach for `.presence_dot` when you want
    # the visible state, and don't add a bare `user.presence ||` chain.
    enum :presence, %i[available away do_not_disturb], default: :available
  end

  # The dot is deliberately not a stored value: it's manual intent resolved
  # against two liveness facts we learn separately. Both are passed in rather
  # than looked up, so a list can batch them (see .presence_dots_for) instead of
  # issuing two queries per avatar.
  #
  # Order matters and encodes the product rule: being unreachable outranks
  # whatever you claimed, a claim outranks inferred idleness, and only the
  # default "available" is open to being second-guessed by idleness at all.
  def presence_dot(connected:, active:)
    return nil if deactivated? || banned?
    return :offline unless connected
    return :dnd if do_not_disturb?
    return :away if away?

    active ? :active : :idle
  end

  def active_now?
    last_active_at.present? && last_active_at > ACTIVE_WINDOW.ago
  end

  # Reachability, from whichever signal has it. The room heartbeat only speaks
  # while someone is watching a room, so on its own it would file anyone reading
  # their settings as offline; a recent interaction is equally good proof that a
  # tab is open, and it reaches every page. The gap this leaves — a tab parked on
  # a roomless page long enough to go idle — reads as offline rather than idle,
  # which is the safe direction to be wrong in.
  def connected_now?
    active_now? || Membership.connected.exists?(user_id: id)
  end

  # The resolver's inputs for a single user, when there's no list to batch with.
  def presence_dot_now
    presence_dot connected: connected_now?, active: active_now?
  end

  # What the user themselves should see on their own avatar. They're looking at
  # the page, so liveness isn't in question — this is the one case where the
  # manual value speaks for itself.
  def own_presence_dot
    presence_dot connected: true, active: true
  end

  # Three verbs, one rule: each ends in a broadcast when — and only when — the
  # dot other people see actually moved. An ordinary stream of "still here"
  # pings changes nothing and says nothing.
  def change_presence!(state)
    update! presence: state
    touch_last_active # choosing a status is itself a sign of life
    broadcast_presence
  end

  def interacted
    return if reported_recently?

    was_active = active_now?
    touch_last_active
    broadcast_presence unless was_active
  end

  # Doesn't clear the timestamp, ages it out: idleness is derived from the one
  # column so a tab that dies without ever reporting still goes idle on its own
  # rather than staying green forever.
  def went_idle
    return unless active_now?

    update_columns last_active_at: ACTIVE_WINDOW.ago - 1.second
    broadcast_presence
  end

  # Workspace-wide, not per-subject. A per-subject stream is the tighter fan-out,
  # but it means subscribing once per visible avatar — and the same person's dot
  # appears in both the sidebar frame and the main document, two separate renders
  # that can't dedupe against each other. The duplicate subscription that follows
  # is never confirmed, and Action Cable then retries it every 500ms forever.
  # One workspace stream removes the failure mode outright.
  #
  # The payload stays presence-only for the same reason it always did: a DM row
  # or directory row would carry unread counts and admin controls that belong to
  # the viewer, not the subject — and now every member receives it.
  def broadcast_presence
    broadcast_render_to [ Current.account, :presence ],
      partial: "users/presences/dots",
      locals: { user: self, dot: presence_dot_now }
  end

  class_methods do
    # Resolves a whole list against two set-membership lookups instead of two
    # queries per row. Returns user id => dot token (nil for deactivated/banned,
    # which render no dot at all).
    def presence_dots_for(users)
      users = Array(users)
      return {} if users.empty?

      ids = users.map(&:id)
      watching = Membership.connected.where(user_id: ids).distinct.pluck(:user_id).to_set
      active = where(id: ids).where(last_active_at: ACTIVE_WINDOW.ago..).pluck(:id).to_set

      users.index_by(&:id).transform_values do |user|
        is_active = active.include?(user.id)
        user.presence_dot connected: is_active || watching.include?(user.id), active: is_active
      end
    end
  end

  private
    def reported_recently?
      active_now? && last_active_at > ACTIVITY_REFRESH_THRESHOLD.ago
    end

    def touch_last_active
      update_columns last_active_at: Time.current
    end
end
