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
    # Availability is what you chose; presence is what that resolves to once
    # liveness has had its say. Only the first is stored, and it's deliberately
    # not called `presence` — that name is Object#presence on every model.
    enum :availability, %i[available away do_not_disturb invisible], default: :available
  end

  # The dot is deliberately not a stored value: it's manual intent resolved
  # against two liveness facts we learn separately. Both are passed in rather
  # than looked up, so a list can batch them (see .presence_dots_for) instead of
  # issuing two queries per avatar.
  #
  # Order matters and encodes the product rule: choosing to be invisible aims the
  # dot down to offline outright, being unreachable outranks whatever you claimed,
  # a claim outranks inferred idleness, and only the default "available" is open
  # to being second-guessed by idleness at all. Nobody can fake presence upward —
  # invisible is the far end of the same rule, letting you look *gone* while
  # you're demonstrably here.
  def presence_dot(connected:, active:)
    return nil if deactivated? || banned?
    return :offline if invisible?
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
  # manual value speaks for itself. Invisible is shown as its own dot rather than
  # the offline everyone else sees, so the person stays reminded they're hidden.
  def own_presence_dot
    return :invisible if invisible?

    presence_dot connected: true, active: true
  end

  # Three verbs, one rule: each ends in a broadcast when — and only when — the
  # dot other people see actually moved. An ordinary stream of "still here"
  # pings changes nothing and says nothing.
  #
  # The two idle verbs pass rare: false. An inferred active/idle flicker reaches
  # the shells a viewer keeps open all day (own + chrome), but not the opt-in
  # directory/profile/roster pages, which aren't worth a live render for a mouse
  # going still. Only a declared change reaches those; they're correct on load
  # either way. See broadcast_presence.
  def change_availability!(state)
    broadcasting_dot_change do
      update! availability: state
      touch_last_active # choosing a status is itself a sign of life
    end
  end

  def interacted
    return if reported_recently?

    broadcasting_dot_change(rare: false) { touch_last_active }
  end

  # Doesn't clear the timestamp, ages it out: idleness is derived from the one
  # column so a tab that dies without ever reporting still goes idle on its own
  # rather than staying green forever.
  #
  # Refused while activity was just reported — the same freshness the write path
  # throttles on, read the other way: you can't be idle inside the window you
  # just proved you were active in. The signal is one shared column, so without
  # this a second tab going quiet could backdate it out from under a tab that's
  # actively reporting, and a client forging alternating edges could force a
  # write and a fan-out on every faked message. Neither can age out a timestamp
  # that a live tab keeps fresh.
  def went_idle
    return unless active_now?
    return if reported_recently?

    broadcasting_dot_change(rare: false) { update_columns last_active_at: ACTIVE_WINDOW.ago - 1.second }
  end

  # Everyone who keeps a row for you: the people you share a direct message
  # with. Their sidebar row, inbox row, and room header are the only places
  # another person's dot appears on a page they're likely to have open. Group
  # DMs are included even though they draw no single dot — they're small, and
  # counting members per room to exclude them costs more than the actions it
  # would save.
  def presence_audience
    User.where(id: Membership.active.where(room_id: direct_room_ids).where.not(user_id: id).select(:user_id))
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
    # The one rule every verb ends on: do the write, then say something only if
    # the dot other people see actually moved. It's the resolved dot that's
    # compared, never the stored value — which is what makes idleness free for
    # anyone who has already said something about themselves. Away and Do Not
    # Disturb ignore the active/idle distinction entirely, so their tabs going
    # quiet and coming back changes nothing and now announces nothing.
    #
    # rare: threads straight through to broadcast_presence — the idle verbs pass
    # false so an ambient flicker never renders or publishes the opt-in pages.
    def broadcasting_dot_change(rare: true)
      was = presence_dot_now
      yield
      now = presence_dot_now

      broadcast_presence now, rare: rare unless now == was
    end

    # Delivery follows the audience rather than the headcount. Up to three sends,
    # each sized to who can actually be looking:
    #
    #   own    → your footer, on your own stream
    #   chrome → your DM rows and room header, on each partner's stream
    #   rare   → the directory, a profile, a roster — on the workspace stream,
    #            which only those pages subscribe to, so it usually reaches nobody
    #
    # The rare send is skipped for ambient idle flickers (rare: false). It's the
    # one payload that almost always reaches nobody, which makes it the one render
    # almost always thrown away — not paying it on the high-frequency active/idle
    # edge is the whole point. A declared availability change still refreshes those
    # pages live, and they read correctly on load regardless.
    #
    # Subscribing per *viewer* rather than per *subject* also keeps the wire quiet:
    # a page opens exactly one of these, where per-subject streams meant one
    # subscription per visible avatar and the same person appeared in both the
    # sidebar frame and the main document. Duplicates are benign — Action Cable
    # ignores a repeated subscribe, and one confirmation forgets every subscription
    # sharing that identifier (findAll), so nothing retries — but they're pure
    # waste, and per-viewer keying makes them impossible rather than harmless.
    #
    # Payloads stay presence-only, as always: a DM row or directory row would carry
    # unread counts and admin controls belonging to the viewer, not the subject.
    def broadcast_presence(dot = presence_dot_now, rare: true)
      return if suppressed_turbo_broadcasts?

      broadcast_dots_to self, "own", dot
      broadcast_dots_to_each presence_audience, "chrome", dot
      broadcast_dots_to Current.account, "rare", dot if rare
    end

    def direct_room_ids
      Rooms::Direct.active.where(id: memberships.select(:room_id)).select(:id)
    end

    def broadcast_dots_to(streamable, group, dot)
      Turbo::StreamsChannel.broadcast_stream_to streamable, :presence, content: render_dots(group, dot)
    end

    # The payload carries only the subject's own dots, so every recipient gets
    # byte-identical HTML. Rendering once and publishing the same string is the
    # difference between one render and one per partner — broadcast_render_to
    # renders per call, which is why it isn't used here.
    def broadcast_dots_to_each(viewers, group, dot)
      viewers = viewers.to_a
      return if viewers.empty?

      content = render_dots(group, dot)
      viewers.each { |viewer| Turbo::StreamsChannel.broadcast_stream_to viewer, :presence, content: content }
    end

    def render_dots(group, dot)
      ApplicationController.render partial: "users/presences/#{group}",
        locals: { user: self, dot: dot }, formats: [ :turbo_stream ]
    end

    def reported_recently?
      active_now? && last_active_at > ACTIVITY_REFRESH_THRESHOLD.ago
    end

    def touch_last_active
      update_columns last_active_at: Time.current
    end
end
