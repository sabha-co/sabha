class Account::JoinCode < ApplicationRecord
  CODE_LENGTH = 12
  DEFAULT_EXPIRATION = 7.days

  belongs_to :account
  belongs_to :user, optional: true

  validates :code, uniqueness: true

  scope :active, -> { where("(usage_limit IS NULL OR usage_count < usage_limit) AND (expires_at IS NULL OR expires_at > ?)", Time.current) }
  scope :global, -> { where(user_id: nil) }
  scope :personal, -> { where.not(user_id: nil) }

  before_validation :generate_code, on: :create, if: -> { code.blank? }
  before_validation :set_default_expiration, on: :create, if: :personal?
  before_validation :set_account_from_current, on: :create, if: -> { account_id.blank? }

  def redeem
    with_lock do
      return false unless active?
      increment!(:usage_count)
      true
    end
  end

  def active?
    !expired? && (unlimited? || usage_count < usage_limit)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def global?
    user_id.nil?
  end

  def personal?
    !global?
  end

  def regenerate_code
    update!(code: generate_new_code, usage_count: 0)
  end

  def unlimited?
    usage_limit.nil?
  end

  def usage_display
    unlimited? ? "#{usage_count} uses" : "#{usage_count}/#{usage_limit} uses"
  end

  private

  def generate_code
    self.code = generate_new_code
  end

  def generate_new_code
    loop do
      candidate = SecureRandom.base58(CODE_LENGTH).scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(code: candidate)
    end
  end

  def set_default_expiration
    self.expires_at ||= DEFAULT_EXPIRATION.from_now
  end

  def set_account_from_current
    self.account = Current.account
  end
end
