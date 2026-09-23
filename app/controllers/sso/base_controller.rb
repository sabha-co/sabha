class Sso::BaseController < ApplicationController
  include BlockBannedRequests

  SESSION_NONCE_KEYS = { custom: "single_sign_on_nonce", hub: "hub_sign_on_nonce" }.freeze

  layout "session"

  allow_unauthenticated_access

  before_action :reject_banned_ip

  private
    # /session/sso is the community's own single sign-on; /session/hub is sabha.co
    def provider
      @provider ||= Sso::Provider.find(request.path_parameters[:provider])
    end

    def sso_configured?
      provider.configured?
    end

    def sso_secret
      provider.secret
    end

    def sso_provider_url
      provider.url
    end

    def session_nonce_key
      SESSION_NONCE_KEYS.fetch(provider.key)
    end

    def provider_callback_url
      provider.hub? ? hub_callback_url : sso_callback_url
    end

    def sso_return_path
      requested_return_path = params[:return_to].presence || session[:return_to_after_authenticating].presence || root_url
      safe_return_path(requested_return_path)
    end

    def safe_return_path(path)
      safe_redirect_url?(path) ? path : root_url
    end

    def sso_misconfigured
      if provider.hub?
        @message = "Signing in with sabha.co isn't available here."
        render "sso/failed", status: :not_found
      else
        Rails.logger.error("[SSO] Missing SSO_PROVIDER_URL or SSO_SECRET")
        @message = "Single sign-on is not configured."
        render "sso/failed", status: :service_unavailable
      end
    end
end
