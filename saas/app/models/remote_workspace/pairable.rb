# frozen_string_literal: true

# "Continue with sabha.co" for a workspace whose admin paired it. The pairing
# lives on the shared row: one active secret per workspace, whoever set it up,
# so controlling the server, not the original account, owns it.
module RemoteWorkspace::Pairable
  extend ActiveSupport::Concern

  PAIRING_PROOF_CONTEXT = "sabha-hub-pairing:"
  CALLBACK_PATH = "/session/hub/callback"

  class NotPairedError < StandardError; end
  class DisconnectedError < StandardError
    attr_reader :remote_workspace

    def initialize(remote_workspace)
      @remote_workspace = remote_workspace
      super("#{remote_workspace.origin} is no longer paired")
    end
  end

  included do
    enum :pairing_status, %w[ none active disconnected ].index_by(&:itself), prefix: :pairing, default: "none"
    enum :paired_via, %w[ self_serve sabha_cloud ].index_by(&:itself), prefix: true

    # Signs sign-in answers, as an env client's secret does
    encrypts :secret

    belongs_to :paired_by, class_name: "GlobalIdentity", optional: true
    has_many :pairing_requests, class_name: "RemoteWorkspacePairingRequest", dependent: :destroy
  end

  class_methods do
    # The paired workspace a sign-in request comes from, found by the address
    # it wants the answer sent to and checked against that workspace's secret
    # alone. Requests for any other return path belong to the env clients.
    def authenticate_sign_in(encoded_payload, signature)
      return_url = Sso::Payload.unverified_return_url(encoded_payload)
      return unless URI(return_url.to_s).path == CALLBACK_PATH

      remote_workspace = find_by(origin: RemoteWorkspace::Origin.normalize(return_url))
      raise DisconnectedError, remote_workspace if remote_workspace&.pairing_disconnected?
      raise NotPairedError unless remote_workspace&.pairing_active?

      payload = Sso::Payload.decode(encoded_payload, signature, remote_workspace.secret)
      raise Sso::Payload::InvalidPayload, "Missing SSO nonce" if payload.nonce.blank?

      [ remote_workspace, payload ]
    rescue URI::InvalidURIError, RemoteWorkspace::Origin::Error
      raise NotPairedError
    end

    # A Sabha Cloud droplet, paired as it's provisioned. The platform created
    # the server, so there's nothing to prove, and the droplet may not answer
    # yet: the name is Cloud's until the daily refresh reads the manifest.
    def pair_sabha_cloud!(address, name:, owner_email: nil)
      create_or_find_by!(origin: RemoteWorkspace::Origin.normalize(address)) { it.name = name }.tap do |remote_workspace|
        remote_workspace.pair_sabha_cloud!
        list_for_owner(remote_workspace, owner_email) if owner_email.present?
      end
    end

    def pairing_proof(secret, origin)
      OpenSSL::HMAC.hexdigest("sha256", secret, "#{PAIRING_PROOF_CONTEXT}#{origin}")
    end

    private
      # The droplet is paired either way; a full list just goes without it,
      # and the platform API reports that as listed: false
      def list_for_owner(remote_workspace, owner_email)
        GlobalIdentity.find_by(email_address: owner_email.to_s.downcase)&.list_sabha_cloud_workspace!(remote_workspace)
      rescue GlobalIdentity::RemoteWorkspaceLimitReachedError
        nil
      end
  end

  # A verified request replaces whatever pairing came before it
  def pair!(request)
    transaction do
      update!(secret: request.secret, pairing_status: :active, paired_via: :self_serve,
        paired_by: request.global_identity, paired_at: Time.current)
      request.destroy!
    end
  end

  # Every deploy asks again, and gets the secret the droplet already runs with.
  # Two retries at once would each mint a secret and one droplet would keep
  # the loser's, so the check runs on the locked, freshly read row.
  def pair_sabha_cloud!
    with_lock do
      unless pairing_active? && paired_via_sabha_cloud?
        update!(secret: SecureRandom.hex(32), pairing_status: :active, paired_via: :sabha_cloud, paired_by: nil, paired_at: Time.current)
      end
    end
    self
  end

  def paired_by?(global_identity)
    pairing_active? && paired_by_id == global_identity.id
  end

  def listed_by?(global_identity)
    memberships.exists?(global_identity: global_identity)
  end

  # Members keep their entries; each falls back to the workspace's own login,
  # and sabha.co asks again before vouching for anyone if it's paired again.
  def disconnect!
    transaction do
      update!(secret: nil, pairing_status: :disconnected)
      memberships.update_all(consented_at: nil)
    end
  end

  def signed_in!
    touch(:last_signed_in_at)
  end
end
