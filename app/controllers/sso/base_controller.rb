class Sso::BaseController < ApplicationController
  layout "session"

  allow_unauthenticated_access

  private
    def sso_configured?
      Current.account&.sso_configured?
    end

    def sso_secret
      Current.account.sso_secret
    end

    def sso_provider_url
      Current.account.sso_provider_url
    end

    def sso_return_path
      requested_return_path = params[:return_to].presence || session[:return_to_after_authenticating].presence || root_url
      safe_return_path(requested_return_path)
    end

    def safe_return_path(path)
      safe_redirect_url?(path) ? path : root_url
    end

    def sso_misconfigured
      Rails.logger.error("[SSO] Missing SSO_PROVIDER_URL or SSO_SECRET")
      @message = "Single sign-on is not configured."
      render "sso/failed", status: :service_unavailable
    end
end
