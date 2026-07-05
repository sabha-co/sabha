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
        # A forum post derives access from its forum, so a member reaches it
        # (typing, presence) without a per-post membership. An outsider resolves
        # nil and is rejected.
        current_user&.rooms&.find_by(id: params[:room_id]) ||
          current_user&.reachable_post(params[:room_id])
      end
    end
end
