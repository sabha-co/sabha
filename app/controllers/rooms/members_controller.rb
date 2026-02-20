# Admin roster management — add/remove members on behalf of others.
# See also Rooms::MembershipsController for self-service join/leave.
class Rooms::MembersController < ApplicationController
  include RoomScoped

  before_action :ensure_can_administer, only: %i[ create destroy ]

  def index
    members = @room.visible_users.active.includes(avatar_attachment: :blob).ordered
    set_page_and_extract_portion_from members, per_page: 25
    @members = @page.records
  end

  def create
    user = User.find(params[:user_id])
    @room.add_member!(user, actor: Current.user)
    broadcast_sidebar_room_added(user, @room, formats: [ :html ])

    render turbo_stream: [
      turbo_stream.update("room_#{@room.id}_member_count", @room.active_member_count.to_s),
      turbo_stream.append("room_#{@room.id}_preview_members",
        partial: "rooms/closeds/user", locals: { user: user, room: @room, selected: true })
    ]
  end

  def destroy
    user = @room.users.find(params[:id])
    @room.remove_member!(user, actor: Current.user)
    broadcast_sidebar_room_removed(user, @room)

    render turbo_stream: turbo_stream.update("room_#{@room.id}_member_count", @room.active_member_count.to_s)
  rescue Membership::LastVisibleMemberError
    head :unprocessable_entity
  end
end
