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
    # When room_id is given, scopes to that room's members. Otherwise spans all
    # rooms the bot shares — narrower than Autocompletable::UsersController, which
    # falls back to User.all. Bots are typically invited to a single room and
    # shouldn't double as workspace people search.
    #
    # For @{user_id} mentions to resolve, callers MUST pass the room_id they intend
    # to post in — API::Bots::MessagesController#format_mentions only resolves IDs
    # found in the target room. A user discoverable via the cross-room form may be
    # silently un-mentionable elsewhere.
    def visible_users
      base_users.active.without_default_names
    end

    def base_users
      params[:room_id].present? ? scoped_room.users : User.sharing_rooms_with(Current.user)
    end

    def scoped_room
      Current.user.rooms.find(params[:room_id])
    end
end
