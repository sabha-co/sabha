class Sso::BaseController < ApplicationController
  include BlockBannedRequests

  SESSION_NONCE_KEY = "single_sign_on_nonce"

  layout "session"

  allow_unauthenticated_access

  before_action :reject_banned_ip

  private
    def sso_configured?
      account_for_sso.sso_configured?
    end

    def sso_secret
      account_for_sso.sso_secret
    end

    def sso_provider_url
      account_for_sso.sso_provider_url
    end

    # Falls back to an unsaved Account so SSO handshake/callback work on a
    # fresh install (no Account yet) — the relevant accessors read ENV.
    def account_for_sso
      Current.account || Account.new
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
