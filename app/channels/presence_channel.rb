class PresenceChannel < RoomChannel
  include AnyCable::Rails::Channel::Presence

  # Has this subscription already given its connection back? Channel state, not
  # an instance variable: every command arrives as its own RPC with a fresh
  # channel object, so an ivar set in `absent` would be gone by `depart`.
  state_attr_accessor :departed

  on_subscribe   :present, unless: :subscription_rejected?
  on_unsubscribe :depart,  unless: :subscription_rejected?

  def present
    with_tenant_context do
      m = membership
      return unless m

      m.present
      join_presence room_presence_stream
      self.departed = false
      ReadRoomsChannel.broadcast_to(current_user, { room_id: m.room_id })
    end
  end

  # A tab going hidden while staying subscribed: AnyCable won't auto-remove
  # presence (the subscription lives on), so we leave it ourselves. The stream
  # is still active, so this never races a teardown.
  def absent
    with_tenant_context do
      leave_presence
      depart_once
    end
  end

  def refresh
    with_tenant_context do
      membership&.refresh_connection
    end
  end

  private
    # after_unsubscribe fires on both graceful unsubscribe and disconnect. In
    # both cases AnyCable removes our presence entry on its own — at once on
    # unsubscribe, after presence_ttl on disconnect — so calling leave_presence
    # here is redundant and races the stream teardown ("stream not found").
    # Only run the connection bookkeeping.
    def depart
      with_tenant_context do
        depart_once
      end
    end

    # A subscription contributes exactly one connection, so it may only take one
    # away. A hidden tab has already sent `absent`; closing it then fires
    # unsubscribe too, and without this guard that second decrement would come
    # out of another tab's count — marking a room unread while the member is
    # still sitting in it.
    def depart_once
      return if departed

      membership&.disconnected
      self.departed = true
    end

    def membership
      with_tenant_context do
        room&.memberships&.find_by(user: current_user)
      end
    end

    # The room's own stream, already tenant-scoped by the Room GID. Passed
    # explicitly so a standalone `present` action (a re-focused tab, no fresh
    # `stream_for`) still joins the right presence set.
    def room_presence_stream
      self.class.broadcasting_for(room)
    end

    # Key presence by the user, so a member's multiple tabs dedupe to one entry
    # and a consumer reads a plain user id rather than a connection GID.
    def user_presence_id
      current_user.id
    end
end
