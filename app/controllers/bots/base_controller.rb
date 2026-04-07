class Bots::BaseController < ApplicationController
  skip_forgery_protection
  allow_bot_access

  before_action :require_bot_authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private
    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def require_creator
      head :forbidden unless @room.creator_id == Current.user.id
    end

    def not_found
      render json: { error: "Not found", code: "not_found" }, status: :not_found
    end
end
