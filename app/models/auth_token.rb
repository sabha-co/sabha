class AuthToken < ApplicationRecord
  # OTP code for User authentication (self-hosted mode)
  #
  # Two authentication methods:
  # - code: 6-character OTP sent via email, entered manually
  # - token: Secure token for direct auto-login links (used by campfire_cloud)
  #
  # Records are marked as used (not deleted) to preserve audit trail.
  # Contrast with SaaS AuthCode which deletes records after use.

  belongs_to :user

  has_secure_token :token

  validates :code, :expires_at, presence: true

  before_validation :generate_code

  scope :valid, -> { where(used_at: nil, expires_at: Time.current..) }

  def deliver_later
    AuthTokenMailer.otp(self).deliver_later
  end

  def use!
    update!(used_at: Time.current)
    user.auth_tokens.without(self).update_all(expires_at: Time.current)
  end

  def self.lookup(token: nil, email_address: nil, code: nil)
    if token.present?
      return valid.find_by(token: token)
    elsif email_address.present? && code.present?
      user = User.find_by(email_address: email_address)
      # Sanitize code input for typo tolerance (O→0, I→1, L→1)
      sanitized_code = OtpCode.sanitize(code)
      return valid.find_by(user: user, code: sanitized_code)
    end

    nil
  end

  private
    def generate_code
      # Use shared OtpCode module for alphanumeric typo-tolerant codes
      self.code ||= OtpCode.generate(6)
    end
end
