# Admin roster management — the Members tab's roster (index), plus add/remove on
# behalf of others. See also Rooms::MembershipsController for self-service leave.
class Rooms::MembersController < ApplicationController
  include RoomScoped

  before_action :ensure_can_administer, only: %i[ create destroy ]
  before_action :set_editable, only: :index

  # No query: the paginated roster, loaded eagerly and scrolled infinitely.
  # A query: one search over everyone this room could hold — matching members
  # (to remove) and, for an editor, matching non-members (to add).
  def index
    if params[:query].present?
      @members = @room.visible_users.active.matching(params[:query], limit: 10)
      @addables = @room.addable_users.matching(params[:query], limit: 10) if @editable
      render :search, layout: false
    else
      members = @room.visible_users.active.includes(avatar_attachment: :blob).ordered
      set_page_and_extract_portion_from members, per_page: 25
      @members = @page.records
    end
  end

  def create
    user = User.find(params[:user_id])
    @room.add_member!(user, actor: Current.user)
    broadcast_sidebar_room_added(user, @room, formats: [ :html ])

    render turbo_stream: [
      turbo_stream.update("room_#{@room.id}_member_count", @room.active_member_count.to_s),
      turbo_stream.prepend("room_members_list",
        partial: "rooms/members/member_row", locals: { user: user, room: @room, editable: true })
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

  private
    def set_editable
      @editable = Current.user.can_administer?(@room) && @room.is_a?(Rooms::Closed)
    end
end
