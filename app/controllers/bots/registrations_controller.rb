class Bots::RegistrationsController < ApplicationController
  include BlockBannedRequests

  allow_unauthenticated_access only: :create
  allow_bot_access only: :create

  rate_limit to: 10, within: 1.hour, only: :create,
    with: -> { render json: { error: "Too many attempts", code: "rate_limited" }, status: :too_many_requests }

  before_action :reject_banned_ip, only: :create
  before_action :verify_self_registration_enabled
  before_action :set_join_code!
  before_action :verify_join_code_active

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Invalid join code", code: "join_code_not_found" }, status: :not_found
  end

  def create
    ActiveRecord::Base.transaction do
      @join_code.redeem!
      @bot = User.create_bot!(bot_params)
    end
    render json: registration_response, status: :created
  rescue Account::JoinCode::InactiveCodeError
    render json: { error: "Join code is no longer valid", code: "join_code_inactive" }, status: :gone
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def verify_self_registration_enabled
      unless Current.account.settings.allow_bot_self_registration?
        render json: { error: "Bot self-registration is not enabled", code: "self_registration_disabled" }, status: :forbidden
      end
    end

    def set_join_code!
      @join_code = Current.account.join_codes.find_by!(code: params[:join_code])
    end

    def verify_join_code_active
      render json: { error: "Join code has expired", code: "join_code_expired" }, status: :gone unless @join_code.active?
    end

    def bot_params
      params.permit(:name, :mentions_url, :everything_url).to_h
    end

    def registration_response
      @bot.reload

      {
        bot_key: @bot.bot_key,
        name: @bot.name,
        webhooks: { mentions_url: @bot.mentions_url, everything_url: @bot.everything_url },
        rooms: @bot.rooms.without_threads.map { |room|
          room.as_bot_json(bot_key: @bot.bot_key, url_helper: method(:room_bot_messages_url))
        }
      }
    end
end
