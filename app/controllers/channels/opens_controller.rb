class Channels::OpensController < ChannelsController
  before_action :set_channel, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :remember_last_channel_visited, only: :show
  before_action :force_channel_type, only: %i[ edit update ]
  before_action :ensure_permission_to_create_channels, only: %i[ new create ]

  DEFAULT_CHANNEL_NAME = "New channel"

  def show
    redirect_to channel_url(@channel)
  end

  def new
    @channel = Channels::Open.new(name: DEFAULT_CHANNEL_NAME)
  end

  def create
    @channel = Channels::Open.create_for(channel_params, users: Current.user)

    broadcast_create_channel
    redirect_to channel_url(@channel)
  end

  def edit
    load_users_for_access_management
  end

  def update
    old_name = @channel.name

    @channel.update! channel_params
    @channel.announce_rename(old_name, actor: Current.user) if @channel.name != old_name

    ChannelUpdateBroadcastJob.perform_later(@channel)
    redirect_back fallback_location: channel_url(@channel), notice: "Changes saved"
  end

  private
    # Open and closed channels convert into each other, so both are in reach here.
    # Nothing else is: promoting a direct channel or a thread would republish its
    # conversation to the whole account.
    def serves?(channel)
      channel.convertible?
    end

    # Allows us to edit a closed channel and turn it into an open one on saving.
    def force_channel_type
      @channel = @channel.becomes!(Channels::Open)
    end

    def broadcast_create_channel
      @channel.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_channel_added(membership.user, @channel)
      end
    end
end
