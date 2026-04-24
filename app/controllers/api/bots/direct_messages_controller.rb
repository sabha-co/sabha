class API::Bots::DirectMessagesController < API::Bots::BaseController
  def create
    @room = Rooms::Direct.find_or_create_for(selected_users)
    render json: { room: { id: @room.id } }, status: (@room.previously_new_record? ? :created : :ok)
  rescue => e
    message = Rails.env.local? ? e.message : "Internal server error"
    render json: { error: message, code: "internal_error" }, status: :internal_server_error
  end

  private
    def selected_users
      User.where(id: params.fetch(:user_ids, []).including(Current.user.id))
    end
end
