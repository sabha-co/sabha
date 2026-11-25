class Channels::DirectsController < ChannelsController
  include ActiveStorage::SetCurrent, NotifyBots

  skip_before_action :set_channel, only: %i[ edit destroy ]
  skip_before_action :ensure_can_administer, only: %i[ destroy ]

  before_action :set_direct_channel, only: %i[ edit destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_permission_to_create_direct_messages, only: %i[ new create ]

  def new
    # With recipients chosen, this doubles as the provisional compose surface: it
    # writes nothing, so a started-but-abandoned conversation leaves no channel, no
    # memberships, and never touches the other person's sidebar. A cached "Message
    # X" link can outlive the empty state, so if a DM already exists, show it
    # rather than a provisional surface that would hide the conversation.
    return @channel = Channels::Direct.new if selected_users_ids.none?

    if existing = Channels::Direct.for(selected_users)
      redirect_to channel_url(existing)
    else
      @recipients = selected_users
    end
  end

  def create
    # The first message materializes the DM (Channels::Direct.message_to) and only
    # then broadcasts it into the recipient's sidebar — no unsolicited empty
    # conversation. Broadcasting mirrors MessagesController#create so the first
    # message reaches the recipient the same way every later one does.
    @message = Channels::Direct.message_to(selected_users, creator: Current.user, message_params: message_params)

    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)

    redirect_to channel_url(@message.channel)
  rescue ActiveRecord::RecordInvalid, Channels::Direct::BlankMessageError
    # A blank or invalid first message created nothing (the transaction rolled back
    # the just-opened DM). Re-render the provisional surface so the composer stays.
    @recipients = selected_users
    render :new, status: :unprocessable_entity
  end

  def edit
    @users = @channel.users.many? ? @channel.users.without(Current.user) : @channel.users
  end

  def destroy
    deactivate_channel
    redirect_to root_url
  end

  private
    def serves?(channel)
      channel.direct?
    end

    def set_direct_channel
      @channel = Current.user.channels.find_by(id: params[:id], type: Channels::Direct.sti_name)
      redirect_to root_url, alert: "Conversation not found" unless @channel
    end

    def set_membership
      @membership = Current.user.memberships.find_by(channel: @channel)
    end

    def selected_users
      User.where(id: selected_users_ids.including(Current.user.id))
    end

    def selected_users_ids
      params.fetch(:user_ids, [])
    end

    def message_params
      params.require(:message).permit(:body, :attachment, :client_message_id)
    end

    def ensure_permission_to_create_direct_messages
      head :forbidden unless Current.user.can_create_direct_messages?
    end
end
