class API::Bots::RegistrationsController < API::Bots::BaseController
  include BlockBannedRequests

  skip_before_action :require_bot_authentication
  allow_unauthenticated_access only: :create

  rate_limit to: 10, within: 1.hour, only: :create,
    with: -> { render json: { error: "Too many attempts", code: "rate_limited" }, status: :too_many_requests }

  before_action :reject_banned_ip, only: :create
  before_action :set_join_code!
  before_action :verify_join_code_active

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Invalid join code", code: "join_code_not_found" }, status: :not_found
  end

  def create
    @join_code.transaction do
      @join_code.redeem!
      @bot = User.create_bot!(bot_params)
    end
    @bot.reload
    @base_url = "#{request.base_url}#{request.script_name}"
    render :create, status: :created
  rescue Account::JoinCode::InactiveCodeError
    render json: { error: "Join code is no longer valid", code: "join_code_inactive" }, status: :gone
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
  end

  private
    def set_join_code!
      @join_code = Current.account.join_codes.bot.find_by!(code: params[:join_code])
    end

    def verify_join_code_active
      render json: { error: "Join code has expired", code: "join_code_expired" }, status: :gone unless @join_code.active?
    end

    def bot_params
      params.permit(:name, :webhook_url, :mentions_url, :everything_url).to_h
    end

    def websocket_url_for_bot
      base = ActionCable.server.config.url || "#{@base_url}/cable"
      base = base.sub(%r{\Ahttps://}, "wss://").sub(%r{\Ahttp://}, "ws://")
      query = { bot_key: @bot.bot_key }
      query[:wid] = ApplicationRecord.current_tenant if Sabha.saas?
      "#{base}?#{query.to_query}"
    end
    helper_method :websocket_url_for_bot
end
