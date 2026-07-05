class RoomChannel < ApplicationCable::Channel
  def subscribed
    if @room = find_room
      stream_for @room
    else
      reject
    end
  end

  private
    def room
      @room ||= find_room
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
