# frozen_string_literal: true

# "Continue with sabha.co" for a community whose admin paired it. The pairing
# lives on the shared row: one active secret per community, whoever set it up,
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

    belongs_to :paired_by, class_name: "GlobalIdentity", optional: true
    has_many :pairings, class_name: "RemoteWorkspacePairing", dependent: :destroy
  end

  class_methods do
    # The paired community a sign-in request comes from, found by the address
    # it wants the answer sent to and checked against that community's secret
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

    def pairing_proof(secret, origin)
      OpenSSL::HMAC.hexdigest("sha256", secret, "#{PAIRING_PROOF_CONTEXT}#{origin}")
    end
  end

  def secret
    hub_secret
  end

  # A verified request replaces whatever pairing came before it
  def pair!(pairing)
    transaction do
      update!(hub_secret: pairing.secret, pairing_status: :active, paired_via: :self_serve,
        paired_by: pairing.global_identity, paired_at: Time.current)
      pairing.destroy!
    end
  end

  # Members keep their entries; each falls back to the community's own login,
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
