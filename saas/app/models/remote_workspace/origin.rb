# frozen_string_literal: true

require "addressable/uri"

# One workspace per origin, so the origin is its identity. Every way into the
# list goes through here, so "HTTPS://Chat.Acme.org:443/rooms" and
# "chat.acme.org" land on the same row.
module RemoteWorkspace::Origin
  extend self

  class Error < StandardError; end
  class Invalid < Error; end

  # The address points at sabha.co itself. When it names a workspace
  # (sabha.co/1000121), `workspace_id` carries it so the caller can send the
  # person to that workspace's join flow instead.
  class Hub < Error
    attr_reader :workspace_id

    def initialize(workspace_id = nil)
      @workspace_id = workspace_id
      super("That's a sabha.co address")
    end
  end

  def normalize(input)
    uri = parse(input.to_s.strip)
    scheme = uri.scheme.downcase
    host = uri.normalized_host.to_s.delete_suffix(".")

    raise Invalid, "Use an https:// address" unless scheme == "https" || (scheme == "http" && RemoteWorkspace.allow_private_networks)
    raise Invalid, "That isn't a web address" if host.blank? || uri.userinfo.present?

    port = uri.port unless uri.port.nil? || uri.port == uri.default_port
    authority = "#{host}#{":#{port}" if port}"
    raise Hub.new(uri.path[%r{\A/(\d+)(?:/|\z)}, 1]) if authority == hub_authority

    "#{scheme}://#{authority}"
  end

  private
    def parse(input)
      raise Invalid, "Enter an address" if input.empty?
      input = "https://#{input}" unless input.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      uri = Addressable::URI.parse(input)
      raise Invalid, "That isn't a web address" unless uri.scheme.to_s.downcase.in?(%w[ http https ]) && uri.host.present?
      uri
    rescue Addressable::URI::InvalidURIError, ArgumentError
      raise Invalid, "That isn't a web address"
    end

    # APP_HOST carries a port in development (localhost:3000), so compare the
    # whole authority; a self-hosted workspace on localhost:3001 is still remote.
    def hub_authority
      Branding.app_host.to_s.downcase
    end
end
