class Account::JoinCode < ApplicationRecord
  CODE_LENGTH = 12
  DEFAULT_EXPIRATION = 7.days

  enum :kind, human: "human", bot: "bot"

  belongs_to :account
  belongs_to :user, optional: true

  validates :code, uniqueness: true

  scope :active, -> { where("(usage_limit IS NULL OR usage_count < usage_limit) AND (expires_at IS NULL OR expires_at > ?)", Time.current) }
  scope :global, -> { where(user_id: nil) }
  scope :personal, -> { where.not(user_id: nil) }

  before_validation :generate_code, on: :create, if: -> { code.blank? }
  before_validation :set_default_expiration, on: :create, if: :personal?
  before_validation :set_default_account, on: :create, if: -> { account_id.blank? }
  before_validation :set_bot_defaults, on: :create, if: :bot?

  class InactiveCodeError < StandardError; end

  def redeem!
    with_lock do
      raise InactiveCodeError unless active?
      increment!(:usage_count)
    end
  end

  def redeem
    redeem!
    true
  rescue InactiveCodeError
    false
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

    def set_default_account
      self.account = Account.sole
    end

    def set_bot_defaults
      self.usage_limit = 1
    end
end
