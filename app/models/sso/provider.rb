# Who a workspace trusts to vouch for a member: its own single sign-on
# (SSO_PROVIDER_URL, the only way in under AUTH_METHOD=sso) or sabha.co
# (SABHA_HUB_SECRET, one more way in beside password and email codes). Both
# speak the same DiscourseConnect payload. Links are keyed by the issuer, the
# provider's origin, so each can vouch for its own accounts.
class Sso::Provider
  PAIRING_PROOF_CONTEXT = "sabha-hub-pairing:"

  attr_reader :key, :url, :secret

  class << self
    def custom
      new(:custom, url: Account.sso_provider_url, secret: Account.sso_secret)
    end

    def hub
      new(:hub, url: "#{Sabha::HUB_URL}/session/sso", secret: ENV["SABHA_HUB_SECRET"])
    end

    def find(key)
      key.to_s == "hub" ? hub : custom
    end
  end

  def initialize(key, url:, secret:)
    @key, @url, @secret = key, url, secret
  end

  def hub?
    key == :hub
  end

  def configured?
    url.present? && secret.present? && (hub? ? hub_allowed? : Account.sso_configured?)
  end

  def issuer
    self.class.origin_of(url)
  end

  # Published in the manifest so sabha.co can tell the server it's pairing with
  # really holds this secret, and really answers at this origin.
  def pairing_proof(origin)
    OpenSSL::HMAC.hexdigest("sha256", secret, "#{PAIRING_PROOF_CONTEXT}#{origin}")
  end

  # New members arriving through sabha.co need an invite unless the admin opens it up
  def auto_provision?
    hub? ? ENV["SABHA_HUB_AUTO_PROVISION"] == "true" : true
  end

  def self.origin_of(url)
    uri = URI.parse(url.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host

    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}".downcase
  rescue URI::InvalidURIError
    nil
  end

  private
    # Custom single sign-on stays exclusive; sabha.co is never offered beside it
    def hub_allowed?
      !Sabha.saas? && !Account.sso_auth?
    end
end
