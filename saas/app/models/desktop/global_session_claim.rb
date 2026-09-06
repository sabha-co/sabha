# frozen_string_literal: true

class Desktop::GlobalSessionClaim < UntenantedRecord
  self.table_name = "desktop_global_session_claims"

  class Error < StandardError; end
  class Invalid < Error; end
  class Replayed < Error; end

  ACTIVE_TTL = 5.minutes

  belongs_to :global_identity

  validates :token_digest, :nonce, :origin, :return_path, :expires_at, presence: true

  scope :valid, -> { where(used_at: nil, expires_at: Time.current..) }

  def self.issue!(global_identity:, nonce:, origin:, return_path:)
    raw_token = SecureRandom.urlsafe_base64(32)
    claim = create!(
      global_identity: global_identity,
      token_digest: digest(raw_token),
      nonce: nonce,
      origin: origin,
      return_path: return_path,
      expires_at: ACTIVE_TTL.from_now
    )
    claim.raw_token = raw_token
    claim
  end

  def self.redeem!(token:, nonce:, origin:)
    raise Invalid, "claim token missing" if token.blank?

    transaction do
      record = valid.lock.find_by(token_digest: digest(token))
      raise Invalid, "claim not found or expired" if record.blank?
      raise Replayed, "claim already used" if record.used_at.present?
      raise Invalid, "claim origin mismatch" unless record.origin == origin
      raise Invalid, "claim nonce mismatch" unless record.nonce == nonce

      record.use!
      record
    end
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.purge_expired
    where(expires_at: ...Time.current).delete_all
  end

  attr_accessor :raw_token

  def use!
    update!(used_at: Time.current)
  end

  def used?
    used_at.present?
  end
end
