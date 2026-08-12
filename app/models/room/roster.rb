# The room's members split by how recently they were here, for the contextual
# room panel: who is watching now, who was here within the last hour, and how
# many of the rest are offline. Presence is the durable DB signal the activity
# dots already read — the connected refcount plus a fresh last-seen — not a live
# broker call: the panel is rendered, not a hot push path.
class Room::Roster
  # Seen this recently but not currently connected reads as "away" rather than
  # offline: recently here, likely still reachable.
  AWAY_WINDOW = Membership::ACTIVITY_TIERS.fetch(:away)

  def initialize(room)
    @room = room
  end

  def here_now
    @here_now ||= users_for @room.memberships.active.connected
  end

  def away
    @away ||= users_for \
      @room.memberships.active.disconnected.where(connected_at: AWAY_WINDOW.ago..)
  end

  def offline_count
    [ total - here_now.size - away.size, 0 ].max
  end

  def any_present?
    here_now.any? || away.any?
  end

  private
    def total
      @total ||= @room.visible_users.active.count
    end

    def users_for(memberships)
      ids = memberships.pluck(:user_id)
      return [] if ids.empty?

      @room.visible_users.active.where(id: ids)
           .includes(avatar_attachment: :blob).ordered.to_a
    end
end
