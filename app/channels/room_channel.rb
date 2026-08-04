class RoomChannel < ApplicationCable::Channel
  def subscribed
    if room
      stream_for room
    else
      reject
    end
  end

  private
    # Memoized for the length of one command, never across them. Every command
    # arrives as its own RPC with a fresh channel object, so the next one resolves
    # the room again — and re-checks access while it's there, which is why holding
    # it wouldn't be an improvement. AnyCable/InstanceVars can't tell the two
    # apart, so the exemption is here rather than on the whole file.
    def room
      @room ||= find_room # rubocop:disable AnyCable/InstanceVars
    end

    def find_room
      with_tenant_context do
        # A sub-room (forum post or chat thread) derives access from its parent, so
        # a parent member reaches it (typing, presence) without a per-sub-room
        # membership — and a stale, silenced-but-active row can't keep granting it
        # after they lose parent access. An outsider resolves nil and is rejected.
        current_user&.reachable_room(params[:room_id])
      end
    end
end
