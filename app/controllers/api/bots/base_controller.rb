class API::Bots::BaseController < ApplicationController
  skip_forgery_protection
  allow_bot_access

  before_action :require_bot_authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private
    # Resolve a channel the bot can currently reach. A sub-channel (forum post / chat
    # thread) the bot still holds a silenced-but-active membership in after losing
    # parent access must not resolve — re-check derived access so a stale row can't
    # keep granting it. Raises (→ 404) when unreachable, like `channels.find` did.
    def reachable_bot_channel(id)
      channel = Current.user.channels.find(id)
      raise ActiveRecord::RecordNotFound if channel.stale_sub_channel_for?(Current.user)
      channel
    end

    # A message the bot can reach: one whose channel it can currently reach (see
    # reachable_bot_channel — a stale sub-channel the bot left the parent of is rejected).
    # `scope` lets a caller add eager-loads. Raises (→ 404) otherwise.
    def reachable_bot_message(id, scope = Message.active)
      scope.find(id).tap { |message| reachable_bot_channel(message.channel_id) }
    end

    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def require_creator
      head :forbidden unless @channel.creator_id == Current.user.id
    end

    def not_found
      render json: { error: "Not found", code: "not_found" }, status: :not_found
    end
end
