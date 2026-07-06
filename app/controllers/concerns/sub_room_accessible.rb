# Resolving access to a nested sub-room (a chat thread or a forum post), whose
# access derives from its parent rather than a per-sub-room membership. A member
# can open one without a row of their own, and a silenced-but-active row must not
# keep granting access after they lose parent access. Shared by the controllers
# that resolve a room from params (rooms, messages, the @mention picker).
module SubRoomAccessible
  extend ActiveSupport::Concern

  private
    # A sub-room resolved by id, but only if the user can currently view it.
    def viewable_sub_room(room_id)
      room = Room.active.sub_rooms.find_by(id: room_id)
      room if room&.viewable_by?(Current.user)
    end

    # Drops a sub-room resolved via a stale membership: re-check derived access so
    # a member removed from the parent loses it immediately rather than riding an
    # orphaned row. A non-sub-room (a normal sidebar room) passes through untouched.
    def deny_stale_sub_room(room)
      room unless room&.sub_room? && !room.viewable_by?(Current.user)
    end
end
