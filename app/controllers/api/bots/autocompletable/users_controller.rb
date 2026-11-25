class API::Bots::Autocompletable::UsersController < API::Bots::BaseController
  LIMIT = 20

  def index
    base = visible_users

    @users = if params[:query].present?
      base.matching(params[:query], limit: LIMIT)
    elsif params[:channel_id].present?
      base.recent_posters_first(params[:channel_id]).limit(LIMIT)
    else
      base.ordered.limit(LIMIT)
    end
  end

  private
    # See API::Bots::UsersController#visible_users for the rationale.
    # `recent_posters_first` is only used when channel_id is given so blank-query
    # results never reflect activity from channels the bot can't see.
    def visible_users
      base = params[:channel_id].present? ? scoped_channel.users : User.sharing_channels_with(Current.user)
      base.active.without_default_names
    end

    def scoped_channel
      reachable_bot_channel(params[:channel_id])
    end
end
