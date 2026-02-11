class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour
  SESSION_LIFETIME = 30.days

  has_secure_token

  belongs_to :user

  before_create :set_defaults
  after_create_commit :update_user_last_authenticated_at

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.start!(user_agent:, ip_address:)
    create! user_agent: user_agent, ip_address: ip_address
  end

  def resume(user_agent:, ip_address:)
    if last_active_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update! user_agent: user_agent, ip_address: ip_address, last_active_at: Time.now
    end
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  private
    def update_user_last_authenticated_at
      user.update_column(:last_authenticated_at, Time.current)
    end

    def set_defaults
      self.last_active_at ||= Time.now
      self.expires_at ||= SESSION_LIFETIME.from_now
    end
end
