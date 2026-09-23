module DesktopHandoff
  extend ActiveSupport::Concern

  SESSION_KEY = "desktop_handoff"

  private
    def desktop_handoff_requested?
      params[:desktop_handoff].present? &&
        params[:desktop_nonce].present? &&
        params[:desktop_origin].present? &&
        params[:desktop_code_challenge].present?
    end

    # Always replaces what's stored, so an abandoned desktop sign-in can't
    # hijack a later browser sign-in in the same session.
    def store_desktop_handoff_context
      clear_desktop_handoff_context
      return unless desktop_handoff_requested?

      session[SESSION_KEY] = {
        "nonce" => params[:desktop_nonce].to_s,
        "origin" => params[:desktop_origin].to_s,
        "code_challenge" => params[:desktop_code_challenge].to_s,
        "return_path" => desktop_return_path
      }
    end

    def desktop_return_path
      path = params[:return_to].to_s
      path.start_with?("/") && !path.start_with?("//") ? path : root_path
    end

    def desktop_handoff_context
      session[SESSION_KEY]
    end

    def clear_desktop_handoff_context
      session.delete(SESSION_KEY)
    end

    def redirect_to_desktop_claim!(claim)
      redirect_to desktop_claim_url(claim), allow_other_host: true
    end

    def desktop_claim_url(claim)
      query = {
        token: claim.raw_token,
        origin: claim.origin,
        nonce: claim.nonce
      }
      "sabha://session-claim?#{query.to_query}"
    end
end
