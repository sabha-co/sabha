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
        current_user&.rooms&.find_by(id: params[:room_id]) || viewable_forum_post(params[:room_id])
      end
    end

    # A forum post derives access from its forum, so a member reaches it (typing,
    # presence) without a per-post membership — the same fallback the controllers
    # use. An outsider still resolves nil and is rejected.
    def viewable_forum_post(room_id)
      post = Rooms::Post.active.find_by(id: room_id)
      post if post&.viewable_by?(current_user)
    end
end
