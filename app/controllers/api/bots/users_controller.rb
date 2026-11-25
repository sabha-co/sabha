class API::Bots::UsersController < API::Bots::BaseController
  def index
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 100)
    page = [ (params[:page].presence || 1).to_i, 1 ].max

    @users = visible_users.ordered.offset((page - 1) * per_page).limit(per_page)
  end

  def show
    @user = visible_users.find(params[:id])
  end

  private
    # When channel_id is given, scopes to that channel's members. Otherwise spans all
    # channels the bot shares — narrower than Autocompletable::UsersController, which
    # falls back to User.all. Bots are typically invited to a single channel and
    # shouldn't double as workspace people search.
    #
    # For @{user_id} mentions to resolve, callers MUST pass the channel_id they intend
    # to post in — API::Bots::MessagesController#format_mentions only resolves IDs
    # found in the target channel. A user discoverable via the cross-channel form may be
    # silently un-mentionable elsewhere.
    def visible_users
      base_users.active.without_default_names
    end

    def base_users
      params[:channel_id].present? ? scoped_channel.users : User.sharing_channels_with(Current.user)
    end

    def scoped_channel
      reachable_bot_channel(params[:channel_id])
    end
end
