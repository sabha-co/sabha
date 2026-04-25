class API::Bots::Autocompletable::UsersController < API::Bots::BaseController
  LIMIT = 20

  def index
    base = User.active.without_default_names.sharing_rooms_with(Current.user)

    @users = if params[:query].present?
      base.matching(params[:query], limit: LIMIT)
    else
      base.recent_posters_first.limit(LIMIT)
    end
  end
end
