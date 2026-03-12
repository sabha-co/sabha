class Bots::ProfilesController < ApplicationController
  allow_bot_access only: :update
  before_action :require_bot_authentication

  def update
    Current.user.update_bot!(bot_params)
    render json: {
      name: Current.user.name,
      webhooks: { mentions_url: Current.user.mentions_url, everything_url: Current.user.everything_url }
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def bot_params
      params.permit(:name, :mentions_url, :everything_url).to_h
    end
end
