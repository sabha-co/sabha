class Ban < ApplicationRecord
  belongs_to :user

  validates :ip_address, presence: true
  validate :ip_address_is_public, if: -> { ip_address.present? && !Rails.env.development? }

  after_save_commit    :bust_cache
  after_destroy_commit :bust_cache

  def self.banned?(ip_address)
    banned_ips.include?(ip_address)
  end

  def self.banned_ips
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) { pluck(:ip_address).to_set }
  end

  def self.cache_key
    if Sabha.saas? && ApplicationRecord.current_tenant.present?
      "#{ApplicationRecord.current_tenant}/banned_ips"
    else
      "banned_ips"
    end
  end

  private
    def bust_cache
      Rails.cache.delete(self.class.cache_key)
    end

    def ip_address_is_public
      ip = IPAddr.new(ip_address)

      if ip.loopback? || ip.private? || ip.link_local?
        errors.add(:ip_address, "cannot be a private or internal IP address")
      end
    rescue IPAddr::InvalidAddressError
      errors.add(:ip_address, "is not a valid IP address")
    end
end
