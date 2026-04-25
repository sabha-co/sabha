class API::Bots::UsersController < API::Bots::BaseController
  def index
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 100)
    page = [ (params[:page].presence || 1).to_i, 1 ].max

    @users = User.active.without_default_names.ordered
      .offset((page - 1) * per_page).limit(per_page)
  end

  def show
    @user = User.active.without_default_names.find(params[:id])
  end
end
