# frozen_string_literal: true

# Someone asking to pair a workspace with sabha.co. It holds a fresh secret
# until the workspace proves, through its manifest, that it runs with it. Any
# number can wait for one workspace, so a squatter can't block its admin.
class RemoteWorkspacePairingRequest < UntenantedRecord
  EXPIRES_IN = 24.hours

  class ProofMismatchError < StandardError; end

  belongs_to :remote_workspace
  belongs_to :global_identity

  encrypts :secret
  has_secure_token :secret, length: 64
  attribute :expires_at, default: -> { EXPIRES_IN.from_now }

  scope :pending, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  def verify!
    hub_proof = RemoteWorkspace::Probe.new.manifest(remote_workspace.origin).hub_proof
    raise ProofMismatchError unless hub_proof.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(hub_proof, expected_proof)

    remote_workspace.pair!(self)
  end

  def expired?
    expires_at.past?
  end

  private
    def expected_proof
      RemoteWorkspace.pairing_proof(secret, remote_workspace.origin)
    end
end
