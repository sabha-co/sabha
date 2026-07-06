module RoomScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_room
  end

  private
    def set_room
      @membership = Current.user.memberships.find_by!(room_id: params[:room_id])
      @room = @membership.room
      enforce_sub_room_access!
    end

    def set_room_if_found
      @membership = Current.user.memberships.find_by(room_id: params[:room_id])
      @room = @membership&.room
      enforce_sub_room_access!
    end

    # A sub-room membership row never grants access on its own — access derives
    # from the parent room. Removal only silences a follow (the row stays active),
    # so a stale row still resolves above; re-check derived access the same way
    # SubRoomAccessible and User#reachable_room do, and deny when it's gone.
    def enforce_sub_room_access!
      raise ActiveRecord::RecordNotFound if @room&.sub_room? && !@room.viewable_by?(Current.user)
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@room)
    end
end
