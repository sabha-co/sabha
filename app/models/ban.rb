class Ban < ApplicationRecord
  belongs_to :user

  validates :ip_address, presence: true
  validate :ip_address_is_public, if: -> { ip_address.present? }

  def self.banned?(ip_address)
    exists?(ip_address: ip_address)
  end

  private
    def ip_address_is_public
      ip = IPAddr.new(ip_address)

      if ip.loopback? || ip.private? || ip.link_local?
        errors.add(:ip_address, "cannot be a private or internal IP address")
      end
    rescue IPAddr::InvalidAddressError
      errors.add(:ip_address, "is not a valid IP address")
    end
end
