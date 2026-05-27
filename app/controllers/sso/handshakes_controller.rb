class Sso::HandshakesController < Sso::BaseController
  def new
    return sso_misconfigured unless sso_configured?

    nonce = SingleSignOnNonce.issue!(return_path: sso_return_path)
    session[SESSION_NONCE_KEY] = nonce
    sso, sig = Sso::Payload.encode({ nonce: nonce, return_sso_url: sso_callback_url }, sso_secret)

    @provider_action, @provider_params = provider_form_parts(sso:, sig:)
  end

  private
    def provider_form_parts(sso:, sig:)
      uri = URI.parse(sso_provider_url)
      params = Rack::Utils.parse_query(uri.query).merge("sso" => sso, "sig" => sig)
      uri.query = nil
      [ uri.to_s, params ]
    end
end
