class Rooms::Directs::ByBotsController < Rooms::DirectsController
  skip_forgery_protection
  rescue_from StandardError, with: :respond_with_error
  allow_bot_access only: :create

  def create
    @room = Rooms::Direct.find_or_create_for(selected_users)
    render json: { room: { id: @room.id } }, status: (@room.previously_new_record? ? :created : :ok)
  end

  private
    def respond_with_error(error)
      message = Rails.env.local? ? error.message : "Internal server error"
      render json: { error: message, code: "internal_error" }, status: :internal_server_error
    end
end
