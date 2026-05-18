class SsoController < ApplicationController
  layout "session"

  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { head :too_many_requests }

  def new
    if sso_configured?
      nonce = Sso::Nonce.issue(session, return_path: sso_return_path)
      sso, sig = Sso::Payload.encode({ nonce: nonce, return_sso_url: sso_login_url }, sso_secret)

      redirect_to provider_url(sso:, sig:), allow_other_host: true
    else
      sso_misconfigured
    end
  end

  def create
    return sso_misconfigured unless sso_configured?

    payload = Sso::Payload.decode(params[:sso], params[:sig], sso_secret)
    return_path = Sso::Nonce.consume!(
      active_store: session,
      used_store: Sso::Nonce::CacheStore.new(Rails.cache),
      nonce: payload["nonce"]
    )

    if payload["failed"]
      @message = "Single sign-on failed."
      render :failed, status: :unauthorized
    elsif payload["logout"]
      restore_authentication
      terminate_current_session if Current.session.present?
      redirect_to safe_return_path(return_path)
    else
      complete_login(payload, return_path)
    end
  rescue Sso::Payload::Error, Sso::Nonce::Error => error
    Rails.logger.warn("[SSO] Rejected callback: #{error.class.name}: #{error.message}")
    head :forbidden
  end

  private
    def complete_login(payload, return_path)
      result = Sso::UserResolver.resolve(payload)

      if result.failure?
        Rails.logger.warn("[SSO] Resolver failed: #{result.message}")
        @message = "Single sign-on failed."
        render :failed, status: :unauthorized
      elsif result.activation_required?
        @message = result.message
        render :failed, status: :unauthorized
      elsif result.session_allowed?
        start_new_session_for(result.user)
        redirect_to safe_return_path(return_path)
      else
        @message = "Single sign-on failed."
        render :failed, status: :unauthorized
      end
    end

    def sso_configured?
      !Sabha.saas? && Current.account&.auth_method_value == "sso" && sso_provider_url.present? && sso_secret.present?
    end

    def sso_provider_url
      ENV["SSO_PROVIDER_URL"]
    end

    def sso_secret
      ENV["SSO_SECRET"]
    end

    def sso_return_path
      requested_return_path = params[:return_to].presence || session[:return_to_after_authenticating].presence || root_url
      safe_return_path(requested_return_path)
    end

    def safe_return_path(path)
      safe_redirect_url?(path) ? path : root_url
    end

    def provider_url(sso:, sig:)
      uri = URI.parse(sso_provider_url)
      query = Rack::Utils.parse_query(uri.query).merge("sso" => sso, "sig" => sig)
      uri.query = Rack::Utils.build_query(query)
      uri.to_s
    end

    def sso_misconfigured
      Rails.logger.error("[SSO] Missing SSO_PROVIDER_URL or SSO_SECRET")
      @message = "Single sign-on is not configured."
      render :failed, status: :service_unavailable
    end
end
