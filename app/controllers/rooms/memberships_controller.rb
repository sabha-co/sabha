# Self-service join/leave — users manage their own membership.
# See also Rooms::MembersController for admin roster management.
class Rooms::MembershipsController < ApplicationController
  include RoomScoped

  skip_before_action :set_room, only: :create
  before_action :set_joinable_room, only: :create
  before_action :ensure_not_direct_room, only: :destroy

  def create
    @room.accept_join!(Current.user)
    broadcast_sidebar_room_added(Current.user, @room)

    redirect_to room_url(@room), notice: "Joined #{@room.name}"
  end

  def destroy
    @room.accept_leave!(Current.user)
    broadcast_sidebar_room_removed(Current.user, @room)

    redirect_to root_url, notice: "You left #{@room.name}"
  rescue Membership::LastVisibleMemberError
    redirect_back fallback_location: room_url(@room),
                  alert: "You're the last member. Delete the room instead."
  end

  private
    def set_joinable_room
      @room = Rooms::Open.active.find(params[:room_id])
    end

    def ensure_not_direct_room
      redirect_to room_url(@room), alert: "Cannot leave direct messages" if @room.direct?
    end
end
