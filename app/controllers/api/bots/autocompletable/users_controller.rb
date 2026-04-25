class API::Bots::Autocompletable::UsersController < API::Bots::BaseController
  LIMIT = 20

  def index
    base = visible_users

    @users = if params[:query].present?
      base.matching(params[:query], limit: LIMIT)
    elsif params[:room_id].present?
      base.recent_posters_first(params[:room_id]).limit(LIMIT)
    else
      base.ordered.limit(LIMIT)
    end
  end

  private
    # See API::Bots::UsersController#visible_users for the rationale.
    # `recent_posters_first` is only used when room_id is given so blank-query
    # results never reflect activity from rooms the bot can't see.
    def visible_users
      base = params[:room_id].present? ? scoped_room.users : User.sharing_rooms_with(Current.user)
      base.active.without_default_names
    end

    def scoped_room
      Current.user.rooms.find(params[:room_id])
    end
end
