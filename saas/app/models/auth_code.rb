# frozen_string_literal: true

class AuthCode < UntenantedRecord
  # OTP code for GlobalIdentity authentication (SaaS mode)
  #
  # - 6-character alphanumeric code (via shared OtpCode module)
  # - 15-minute expiration
  # - Typo-tolerant (O→0, I/L→1)
  # - Used for both sign-in and sign-up verification
  #
  # Parallels AuthToken in self-hosted mode, but:
  # - Stored in untenanted database (works before workspace selection)
  # - Belongs to GlobalIdentity instead of User


  belongs_to :global_identity

  enum :purpose, { sign_in: 0, sign_up: 1, email_change: 2 }

  validates :code, presence: true, uniqueness: true
  validates :purpose, presence: true

  scope :active, -> { where(expires_at: Time.current..) }

  before_validation :generate_code, on: :create
  before_validation :set_expiration, on: :create

  # Find an active auth code by code string
  # Returns nil if code is invalid or expired
  def self.find_active(code)
    sanitized = OtpCode.sanitize(code)
    active.find_by(code: sanitized)
  end

  # Consume this auth code, returning the global_identity
  def consume
    global_identity.tap { destroy }
  end

  def deliver_later
    AuthCodeMailer.code(self).deliver_later
  end

  def expired?
    expires_at < Time.current
  end

  private

    def generate_code
      self.code ||= OtpCode.generate(6)
    end

    def set_expiration
      self.expires_at ||= 15.minutes.from_now
    end
end
