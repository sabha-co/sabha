class Sso::ProviderClient
  # Registered relying apps allowed to use Sabha SaaS as their SSO identity
  # provider. This is the provider-side complement to the self-hosted SSO
  # consumer config on Account, not another way for a workspace to sign in.
  #
  # sabha.co (Sabha SaaS mode) is the SSO provider / identity authority.
  # cloud.sabha.co (sabha_cloud) is the SSO client / relying app.
  class Error < StandardError; end
  class NotConfigured < Error; end
  class InvalidReturnUrl < Error; end

  DEFAULT_RETURN_PATH = "/session/sso/callback"

  attr_reader :name, :return_host, :return_path, :secret

  def self.authenticate(encoded_payload, signature)
    raise NotConfigured, "No SSO provider clients are configured" if active.none?
    raise Sso::Payload::InvalidPayload, "Missing SSO payload" if encoded_payload.blank?
    raise Sso::Payload::InvalidSignature, "Missing SSO signature" if signature.blank?

    client = active.find { |candidate| Sso::Payload.valid_signature?(encoded_payload, signature, candidate.secret) }
    raise Sso::Payload::InvalidSignature, "Bad signature for payload" unless client

    payload = Sso::Payload.decode(encoded_payload, signature, client.secret)
    raise Sso::Payload::InvalidPayload, "Missing SSO nonce" if payload["nonce"].blank?

    client.verify_return_url!(payload["return_sso_url"])

    [ client, payload ]
  end

  def self.active
    all.select(&:active?)
  end

  def self.all
    ENV.fetch("SSO_PROVIDER_CLIENTS", "").split(",").filter_map do |name|
      from_env(name.strip)
    end
  end

  def self.from_env(name)
    return if name.blank?

    key = name.upcase
    new(
      name: name,
      return_host: ENV["SSO_#{key}_RETURN_HOST"],
      return_path: ENV.fetch("SSO_#{key}_RETURN_PATH", DEFAULT_RETURN_PATH),
      secret: ENV["SSO_#{key}_SECRET"],
      active: ENV.fetch("SSO_#{key}_ACTIVE", "true")
    )
  end

  def initialize(name:, return_host:, return_path:, secret:, active:)
    @name = name
    @return_host = return_host
    @return_path = return_path
    @secret = secret
    @active = active
  end

  def active?
    ActiveModel::Type::Boolean.new.cast(@active) && return_host.present? && secret.present?
  end

  def verify_return_url!(url)
    raise InvalidReturnUrl, "Missing SSO return URL" if url.blank?

    uri = URI.parse(url)

    unless valid_scheme?(uri) && host_matches?(uri.host) && uri.path == return_path && uri.userinfo.blank?
      raise InvalidReturnUrl, "Untrusted SSO return URL"
    end

    true
  rescue URI::InvalidURIError
    raise InvalidReturnUrl, "Invalid SSO return URL"
  end

  # True when this client's return_host is a single-label wildcard like
  # "*.sabha.co" — matching one subdomain level (acme.sabha.co), not the bare
  # apex (sabha.co) or deeper subdomains (evil.acme.sabha.co).
  def wildcard?
    return_host.to_s.start_with?("*.")
  end

  private
    # Production requires HTTPS; development allows plain HTTP so the local
    # cloud.lvh.me ↔ lvh.me SSO loop works without TLS.
    def valid_scheme?(uri)
      return true if uri.is_a?(URI::HTTPS)

      Rails.env.development? && uri.is_a?(URI::HTTP)
    end

    def host_matches?(host)
      return false if host.blank?
      return host == return_host unless wildcard?

      base = return_host.delete_prefix("*.")
      return false unless host.end_with?(".#{base}")

      remainder = host.delete_suffix(".#{base}")
      return false if remainder.empty? || remainder.include?(".")

      # A wildcard client must not validate a host that another configured
      # client claims exactly — keeps managed_sabha (*.sabha.co) out of
      # cloud.sabha.co even if cloud_sabha's secret leaks and an attacker
      # tries to swap return URLs.
      !claimed_exactly_by_other_client?(host)
    end

    def claimed_exactly_by_other_client?(host)
      self.class.active.any? do |client|
        client.name != name && !client.wildcard? && client.return_host == host
      end
    end
end
