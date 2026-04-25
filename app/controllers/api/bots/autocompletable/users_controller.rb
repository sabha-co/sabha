class API::Bots::Autocompletable::UsersController < API::Bots::BaseController
  LIMIT = 20

  def index
    # Scoped to shared rooms — bots aren't given workspace-wide people search.
    # See API::Bots::UsersController#visible_users for the rationale.
    base = User.active.without_default_names.sharing_rooms_with(Current.user)

    @users = if params[:query].present?
      base.matching(params[:query], limit: LIMIT)
    else
      base.recent_posters_first.limit(LIMIT)
    end
  end
end
