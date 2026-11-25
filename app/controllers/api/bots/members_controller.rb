class API::Bots::MembersController < API::Bots::BaseController
  before_action :set_channel
  before_action :require_creator, only: %i[create destroy]

  def index
    members = @channel.memberships.visible.includes(:user).map do |membership|
      user = membership.user
      { id: user.id, name: user.name, role: user.role }
    end

    render json: members
  end

  def create
    user = User.active.find(params[:user_id])
    @channel.add_member!(user, actor: Current.user)
    broadcast_sidebar_channel_added(user, @channel)

    render json: { id: user.id, name: user.name }, status: :created
  end

  def destroy
    user = @channel.users.find(params[:id])
    @channel.remove_member!(user, actor: Current.user)
    broadcast_sidebar_channel_removed(user, @channel)

    head :no_content
  rescue Membership::LastVisibleMemberError
    render json: { error: "Cannot remove the last member", code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def set_channel
      @channel = reachable_bot_channel(params[:channel_id])
    end
end
