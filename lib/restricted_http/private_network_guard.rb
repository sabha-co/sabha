require "surfguard"

# The SSRF address policy lives in the surfguard gem so Sabha classifies
# "internal" the same way Basecamp, HEY, and Campfire do, instead of vendoring
# ranges that drift. Callers hand in a bare hostname and pin the address that
# comes back.
module RestrictedHTTP
  module PrivateNetworkGuard
    extend self

    class Violation < StandardError; end

    # Pin the first public address, or fail loudly. Raises Violation for a host
    # that resolves only to blocked addresses, and lets Surfguard::Unresolvable
    # propagate for one that resolves to nothing -- so a DNS miss is never
    # misreported as an SSRF attempt, and callers that care (webhook URL
    # validation) can rescue the two separately.
    def resolve_public_ip!(hostname)
      Surfguard.resolve_public_ips(hostname).first or
        raise Violation, "#{hostname} resolves only to private or internal addresses"
    end

    # The same address, or nil when the host is blocked, malformed, or
    # unresolvable. Use where "no usable public IP" is an ordinary outcome.
    def resolve_public_ip(hostname)
      resolve_public_ip!(hostname)
    rescue Violation, Surfguard::Unresolvable
      nil
    end
  end
end
