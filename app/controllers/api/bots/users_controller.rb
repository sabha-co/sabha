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
    def visible_users
      User.active.without_default_names.sharing_rooms_with(Current.user)
    end
end
