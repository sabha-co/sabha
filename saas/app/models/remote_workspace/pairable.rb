# frozen_string_literal: true

# "Continue with sabha.co" for a workspace whose admin paired it. The pairing
# lives on the shared row: one active secret per workspace, whoever set it up,
# so controlling the server, not the original account, owns it.
module RemoteWorkspace::Pairable
  extend ActiveSupport::Concern

  PAIRING_PROOF_CONTEXT = "sabha-hub-pairing:"
  CALLBACK_PATH = "/session/hub/callback"

  class NotPaired < StandardError; end
  class Disconnected < StandardError
    attr_reader :remote_workspace

    def initialize(remote_workspace)
      @remote_workspace = remote_workspace
      super("#{remote_workspace.origin} is no longer paired")
    end
  end

  included do
    enum :pairing_status, %w[ none active revoked ].index_by(&:itself), prefix: :pairing, default: "none"
    enum :paired_via, %w[ self_serve sabha_cloud ].index_by(&:itself), prefix: true

    encrypts :hub_secret
    # Signs sign-in answers, as an env client's secret does
    alias_attribute :secret, :hub_secret

    belongs_to :paired_by, class_name: "GlobalIdentity", optional: true
    has_many :pairings, class_name: "RemoteWorkspacePairing", dependent: :destroy
  end

  class_methods do
    # The paired workspace a sign-in request comes from, found by the address
    # it wants the answer sent to and checked against that workspace's secret
    # alone. Requests for any other return path belong to the env clients.
    def authenticate_sign_in(encoded_payload, signature)
      return_url = Sso::Payload.unverified_return_url(encoded_payload)
      return unless URI(return_url.to_s).path == CALLBACK_PATH

      remote_workspace = find_by(origin: RemoteWorkspace::Origin.normalize(return_url))
      raise Disconnected, remote_workspace if remote_workspace&.pairing_revoked?
      raise NotPaired unless remote_workspace&.pairing_active?

      payload = Sso::Payload.decode(encoded_payload, signature, remote_workspace.hub_secret)
      raise Sso::Payload::InvalidPayload, "Missing SSO nonce" if payload.nonce.blank?

      [ remote_workspace, payload ]
    rescue URI::InvalidURIError, RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Origin::Hub
      raise NotPaired
    end

    # A Sabha Cloud droplet, paired as it's provisioned. The platform created
    # the server, so there's nothing to prove, and the droplet may not answer
    # yet: the name is Cloud's until the daily refresh reads the manifest.
    def pair_sabha_cloud!(address, name:, owner_email: nil)
      create_or_find_by!(origin: RemoteWorkspace::Origin.normalize(address)) { it.name = name }.tap do |remote_workspace|
        remote_workspace.pair_sabha_cloud!
        GlobalIdentity.find_by(email_address: owner_email.to_s.downcase)&.list_sabha_cloud_workspace(remote_workspace) if owner_email.present?
      end
    end

    def pairing_proof(secret, origin)
      OpenSSL::HMAC.hexdigest("sha256", secret, "#{PAIRING_PROOF_CONTEXT}#{origin}")
    end
  end

  # A verified request replaces whatever pairing came before it
  def pair!(pairing)
    transaction do
      update!(hub_secret: pairing.secret, pairing_status: :active, paired_via: :self_serve,
        paired_by: pairing.global_identity, paired_at: Time.current)
      pairing.destroy!
    end
  end

  # Every deploy asks again, and gets the secret the droplet already runs with.
  # Two retries at once would each mint a secret and one droplet would keep
  # the loser's, so the check runs on the locked, freshly read row.
  def pair_sabha_cloud!
    with_lock do
      unless pairing_active? && paired_via_sabha_cloud?
        update!(hub_secret: SecureRandom.hex(32), pairing_status: :active, paired_via: :sabha_cloud, paired_by: nil, paired_at: Time.current)
      end
    end
    self
  end

  def connected_by?(global_identity)
    pairing_active? && paired_by_id == global_identity.id
  end

  # A droplet's owner may not have a sabha.co account yet, or a full list
  def listed_by?(email_address)
    memberships.joins(:global_identity).exists?(global_identities: { email_address: email_address.to_s.downcase })
  end

  # Members keep their entries; each falls back to the workspace's own login,
  # and sabha.co asks again before vouching for anyone if it's paired again.
  def disconnect!
    transaction do
      update!(hub_secret: nil, pairing_status: :revoked)
      memberships.update_all(consented_at: nil)
    end
  end

  def signed_in!
    touch(:last_signed_in_at)
  end
end
