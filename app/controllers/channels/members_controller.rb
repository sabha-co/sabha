# Admin roster management — add/remove members on behalf of others.
# See also Channels::MembershipsController for self-service join/leave.
class Channels::MembersController < ApplicationController
  include ChannelScoped

  before_action :ensure_can_administer, only: %i[ create destroy ]

  def index
    members = @channel.visible_users.active.includes(avatar_attachment: :blob).ordered
    set_page_and_extract_portion_from members, per_page: 25
    @members = @page.records
  end

  def create
    user = User.find(params[:user_id])
    @channel.add_member!(user, actor: Current.user)
    broadcast_sidebar_channel_added(user, @channel, formats: [ :html ])

    render turbo_stream: [
      turbo_stream.update("channel_#{@channel.id}_member_count", @channel.active_member_count.to_s),
      turbo_stream.prepend("channel_#{@channel.id}_preview_members",
        partial: "channels/closeds/user", locals: { user: user, channel: @channel, selected: true })
    ]
  end

  def destroy
    user = @channel.users.find(params[:id])
    @channel.remove_member!(user, actor: Current.user)
    broadcast_sidebar_channel_removed(user, @channel)

    render turbo_stream: turbo_stream.update("channel_#{@channel.id}_member_count", @channel.active_member_count.to_s)
  rescue Membership::LastVisibleMemberError
    head :unprocessable_entity
  end
end
