class Sso::HandshakesController < Sso::BaseController
  def new
    return sso_misconfigured unless sso_configured?

    nonce = SingleSignOnNonce.issue!(session:, return_path: sso_return_path)
    sso, sig = Sso::Payload.encode({ nonce: nonce, return_sso_url: sso_callback_url }, sso_secret)

    redirect_to provider_url(sso:, sig:), allow_other_host: true
  end

  private
    def provider_url(sso:, sig:)
      uri = URI.parse(sso_provider_url)
      query = Rack::Utils.parse_query(uri.query).merge("sso" => sso, "sig" => sig)
      uri.query = Rack::Utils.build_query(query)
      uri.to_s
    end
end
