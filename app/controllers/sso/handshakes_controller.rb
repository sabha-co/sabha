class Sso::HandshakesController < Sso::BaseController
  include Handoff

  def new
    return sso_misconfigured unless sso_configured?

    store_handoff_context
    store_pending_join_code if provider.hub?

    nonce = SingleSignOnNonce.issue!(return_path: sso_return_path)
    session[session_nonce_key] = nonce
    sso, sig = Sso::Payload.encode({ nonce: nonce, return_sso_url: provider_callback_url }, sso_secret)

    @provider_action, @provider_params = provider_form_parts(sso:, sig:)
  end

  private
    # "Continue with sabha.co" on an invite page carries the invite through the
    # round trip, so a new member can join by it.
    def store_pending_join_code
      join_code = Current.account&.join_codes&.human&.find_by(code: params[:join_code].to_s) if params[:join_code].present?
      join_code&.active? ? session[:pending_join_code] = join_code.code : session.delete(:pending_join_code)
    end

    def provider_form_parts(sso:, sig:)
      uri = URI.parse(sso_provider_url)
      params = Rack::Utils.parse_query(uri.query).merge("sso" => sso, "sig" => sig)
      uri.query = nil
      [ uri.to_s, params ]
    end
end
