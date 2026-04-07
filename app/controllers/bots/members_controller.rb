class Bots::MembersController < Bots::BaseController
  before_action :require_bot_authentication
  rescue_from ActiveRecord::RecordNotFound, with: :room_not_found

  def index
    room = Current.user.rooms.find(params[:room_id])
    members = room.memberships.visible.includes(:user).map do |membership|
      user = membership.user
      { id: user.id, name: user.name, role: user.role }
    end

    render json: members
  end

  private
    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def room_not_found
      render json: { error: "Room not found", code: "room_not_found" }, status: :not_found
    end
end
