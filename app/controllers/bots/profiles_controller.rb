class Bots::ProfilesController < ApplicationController
  allow_bot_access only: :update

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
    def bot_params
      params.permit(:name, :mentions_url, :everything_url).to_h.symbolize_keys
    end
end
