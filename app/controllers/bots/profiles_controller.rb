class Bots::ProfilesController < Bots::BaseController
  before_action :require_bot_authentication

  def update
    Current.user.update_bot!(bot_params)
    render json: {
      name: Current.user.name,
      webhook_url: Current.user.webhook_url
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def bot_params
      params.permit(:name, :webhook_url, :mentions_url, :everything_url).to_h
    end
end
