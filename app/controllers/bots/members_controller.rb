class Bots::MembersController < Bots::BaseController
  before_action :require_bot_authentication
  before_action :set_room
  before_action :require_creator, only: %i[create destroy]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    members = @room.memberships.visible.includes(:user).map do |membership|
      user = membership.user
      { id: user.id, name: user.name, role: user.role }
    end

    render json: members
  end

  def create
    user = User.active.find(params[:user_id])
    @room.add_member!(user, actor: Current.user)

    render json: { id: user.id, name: user.name }, status: :created
  end

  def destroy
    user = @room.users.find(params[:user_id])
    @room.remove_member!(user, actor: Current.user)

    head :no_content
  rescue Membership::LastVisibleMemberError
    render json: { error: "Cannot remove the last member", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def set_room
      @room = Current.user.rooms.find(params[:room_id])
    end

    def require_creator
      head :forbidden unless @room.creator_id == Current.user.id
    end

    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def not_found
      render json: { error: "Room or user not found", code: "not_found" }, status: :not_found
    end
end
