module RoomScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_room
  end

  private
    def set_room
      @membership = Current.user.memberships.find_by!(room_id: params[:room_id])
      @room = @membership.room
      ensure_sub_room_access
    end

    def set_room_if_found
      @membership = Current.user.memberships.find_by(room_id: params[:room_id])
      @room = @membership&.room
      ensure_sub_room_access
    end

    # A sub-room follow row can outlive the parent access that justified it, so
    # deny one the user can no longer reach — the same re-check SubRoomAccessible
    # and User#reachable_room apply.
    def ensure_sub_room_access
      raise ActiveRecord::RecordNotFound if @room&.stale_sub_room_for?(Current.user)
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@room)
    end
end
