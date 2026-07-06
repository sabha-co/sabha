class API::Bots::BaseController < ApplicationController
  skip_forgery_protection
  allow_bot_access

  before_action :require_bot_authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private
    # Resolve a room the bot can currently reach. A sub-room (forum post / chat
    # thread) the bot still holds a silenced-but-active membership in after losing
    # parent access must not resolve — re-check derived access so a stale row can't
    # keep granting it. Raises (→ 404) when unreachable, like `rooms.find` did.
    def reachable_bot_room(id)
      room = Current.user.rooms.find(id)
      raise ActiveRecord::RecordNotFound if room.sub_room? && !room.viewable_by?(Current.user)
      room
    end

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
