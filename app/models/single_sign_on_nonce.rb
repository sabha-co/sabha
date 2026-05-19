class SingleSignOnNonce < ApplicationRecord
  class Error < StandardError; end
  class Invalid < Error; end
  class Replayed < Error; end

  ACTIVE_TTL = 30.minutes

  before_validation :set_nonce, on: :create
  before_validation :set_expiration, on: :create

  validates :nonce, presence: true, uniqueness: true
  validates :return_path, :expires_at, presence: true

  def self.issue!(session:, return_path:, now: Time.current)
    create!(return_path:, expires_at: ACTIVE_TTL.from_now(now)).tap do |record|
      session[session_key(record.nonce)] = true
    end.nonce
  end

  def self.consume!(nonce, session:, now: Time.current)
    raise Invalid, "SSO nonce expired or invalid" if nonce.blank?

    transaction do
      record = lock.find_by(nonce:)
      raise Invalid, "SSO nonce expired or invalid" if record.blank?
      raise Replayed, "SSO nonce already used" if record.used?
      raise Invalid, "SSO nonce expired or invalid" unless session.delete(session_key(nonce))
      raise Invalid, "SSO nonce expired or invalid" if record.expired?(now:)

      record.use!(now:)
      record.return_path
    end
  end

  def self.session_key(nonce)
    "single_sign_on_nonce_#{nonce}"
  end

  def self.purge_expired
    where(expires_at: ...Time.current).delete_all
  end

  def use!(now: Time.current)
    update!(used_at: now)
  end

  def used?
    used_at.present?
  end

  def expired?(now: Time.current)
    expires_at <= now
  end

  private
    def set_nonce
      self.nonce ||= SecureRandom.hex
    end

    def set_expiration
      self.expires_at ||= ACTIVE_TTL.from_now
    end
end
