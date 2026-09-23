class Desktop::SessionClaim < ApplicationRecord
  self.table_name = "desktop_session_claims"

  class Invalid < StandardError; end

  ACTIVE_TTL = 5.minutes

  belongs_to :user

  validates :token_digest, :nonce, :origin, :code_challenge, :return_path, :expires_at, presence: true

  scope :valid, -> { where(used_at: nil, expires_at: Time.current..) }

  def self.issue!(user:, nonce:, origin:, code_challenge:, return_path:)
    raw_token = SecureRandom.urlsafe_base64(32)
    claim = create!(
      user: user,
      token_digest: digest(raw_token),
      nonce: nonce,
      origin: origin,
      code_challenge: code_challenge,
      return_path: return_path,
      expires_at: ACTIVE_TTL.from_now
    )
    claim.raw_token = raw_token
    claim
  end

  # The deep link carries token, nonce and origin, so any app that intercepts
  # it has all three. Only the client that started the sign-in holds the PKCE
  # verifier (RFC 7636, S256).
  def self.redeem!(token:, nonce:, origin:, code_verifier:)
    raise Invalid, "claim token missing" if token.blank?
    raise Invalid, "code verifier missing" if code_verifier.blank?

    transaction do
      record = valid.lock.find_by(token_digest: digest(token))
      raise Invalid, "claim not found, expired, or used" if record.blank?
      raise Invalid, "claim origin mismatch" unless record.origin == origin
      raise Invalid, "claim nonce mismatch" unless record.nonce == nonce
      raise Invalid, "code verifier mismatch" unless record.verifies?(code_verifier)

      record.use!
      record
    end
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.code_challenge_for(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  def self.purge_expired
    where(expires_at: ...Time.current).delete_all
  end

  attr_accessor :raw_token

  def verifies?(code_verifier)
    ActiveSupport::SecurityUtils.secure_compare(self.class.code_challenge_for(code_verifier), code_challenge)
  end

  def use!
    update!(used_at: Time.current)
  end
end
