# frozen_string_literal: true

class GlobalSession < UntenantedRecord
  # Cross-workspace session token
  #
  # Stored in cookie as :global_session_token
  # Allows switching between workspaces without re-authenticating

  belongs_to :global_identity, touch: true

  has_secure_token :token, length: 40

  validates :token, presence: true, uniqueness: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  before_create :set_expiration

  ACTIVITY_REFRESH_RATE = 30.seconds

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def touch_last_active!
    update_column(:last_active_at, Time.current)
  end

  # Resume session with updated metadata (matches Session#resume behavior)
  # Only updates if enough time has passed to avoid excessive DB writes
  # Also extends expires_at so active users don't get logged out
  def resume(user_agent:, ip_address:)
    if last_active_at.nil? || last_active_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update!(user_agent: user_agent, ip_address: ip_address, last_active_at: Time.current, expires_at: 30.days.from_now)
    end
  end

  private

    def set_expiration
      # Sessions expire after 30 days of inactivity
      # Can be extended by updating last_active_at
      self.expires_at ||= 30.days.from_now
    end
end
