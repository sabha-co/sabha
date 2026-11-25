class Channels::ForumsController < ChannelsController
  before_action :set_channel, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :remember_last_channel_visited, only: :show
  before_action :ensure_permission_to_create_channels, only: %i[ new create ]

  DEFAULT_FORUM_NAME = "New forum"

  # A forum renders at the canonical /channels/:id (ChannelsController#show draws the
  # gallery), same as open/closed channels redirect there.
  def show
    redirect_to channel_url(@channel)
  end

  def new
    @channel = Channels::Forum.new(name: DEFAULT_FORUM_NAME)
  end

  def create
    @channel = Channels::Forum.create_for(forum_params, users: Current.user)

    broadcast_create_channel
    redirect_to channel_url(@channel)
  end

  def edit
    load_users_for_access_management
  end

  def update
    old_name = @channel.name

    @channel.update! forum_params
    @channel.announce_rename(old_name, actor: Current.user) if @channel.name != old_name

    ChannelUpdateBroadcastJob.perform_later(@channel)
    redirect_back fallback_location: channel_url(@channel), notice: "Changes saved"
  end

  private
    def serves?(channel)
      channel.forum?
    end

    def forum_params
      params.require(:channel).permit(:name, :description)
    end

    def broadcast_create_channel
      @channel.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_channel_added(membership.user, @channel)
      end
    end
end
