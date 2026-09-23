# Hands a sign-in finished in the system browser back to a Sabha app. The app
# starts SSO with these parameters; after sign-in the callback issues a
# one-time Session::Claim and redirects to the app's sabha:// link.
module Handoff
  extend ActiveSupport::Concern

  SESSION_KEY = "handoff"

  private
    def handoff_requested?
      params[:handoff].present? &&
        params[:handoff_nonce].present? &&
        params[:handoff_origin].present? &&
        params[:code_challenge].present?
    end

    # Always replaces what's stored, so an abandoned app sign-in can't hijack a
    # later browser sign-in in the same session.
    def store_handoff_context
      clear_handoff_context
      return unless handoff_requested?

      session[SESSION_KEY] = {
        "nonce" => params[:handoff_nonce].to_s,
        "origin" => params[:handoff_origin].to_s,
        "code_challenge" => params[:code_challenge].to_s,
        "return_path" => handoff_return_path
      }
    end

    def handoff_return_path
      path = params[:return_to].to_s
      path.start_with?("/") && !path.start_with?("//") ? path : root_path
    end

    def handoff_context
      session[SESSION_KEY]
    end

    def clear_handoff_context
      session.delete(SESSION_KEY)
    end

    def redirect_to_session_claim!(claim)
      redirect_to session_claim_url(claim), allow_other_host: true
    end

    def session_claim_url(claim)
      "sabha://session-claim?#{{ token: claim.raw_token, origin: claim.origin, nonce: claim.nonce }.to_query}"
    end
end
