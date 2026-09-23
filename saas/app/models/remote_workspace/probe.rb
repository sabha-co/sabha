# frozen_string_literal: true

require "net/http"

# Reads a self-hosted community's public manifest and logo. Every request pins
# a public address, follows no redirects and caps the body, because the origin
# comes from whoever pasted it. It carries nothing about the person asking.
class RemoteWorkspace::Probe
  TIMEOUT = 5.seconds
  MAX_MANIFEST_SIZE = 64.kilobytes
  MAX_LOGO_SIZE = 64.kilobytes
  LOGO_CONTENT_TYPES = %w[ image/png image/jpeg image/webp image/gif ].freeze

  class Error < StandardError; end
  class Unreachable < Error; end
  # Not a Sabha server, or one from before the protocol existed
  class NotSabha < Error; end
  # A Sabha server speaking a different protocol major
  class UnsupportedProtocol < Error; end

  Manifest = Data.define(:name, :logo_url, :alias_origin, :protocol_major, :hub_proof)

  def manifest(origin)
    response, body = get(URI("#{origin}/api/manifest"), accept: "application/json", max_size: MAX_MANIFEST_SIZE)

    case response
    when Net::HTTPOK then parse_manifest(origin, body)
    when Net::HTTPUnsupportedMediaType then raise UnsupportedProtocol
    when Net::HTTPNotFound, Net::HTTPRedirection then raise NotSabha
    else raise Unreachable, "HTTP #{response.code}"
    end
  end

  # [ bytes, content_type ], or nil for anything that isn't a small image
  def logo(url)
    response, body = get(URI(url), accept: LOGO_CONTENT_TYPES.join(", "), max_size: MAX_LOGO_SIZE)
    content_type = response.content_type

    [ body, content_type ] if response.is_a?(Net::HTTPOK) && content_type.in?(LOGO_CONTENT_TYPES)
  rescue Error
    nil
  end

  private
    def get(uri, accept:, max_size:)
      Net::HTTP.start(uri.host, uri.port, ipaddr: address_for(uri.host), use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri, "Accept" => accept, "Sabha-Protocol-Major" => Sabha::PROTOCOL_MAJOR.to_s)
        http.request(request) do |response|
          return [ response, read_capped(response, max_size) ]
        end
      end
    rescue RestrictedHTTP::PrivateNetworkGuard::Violation, Surfguard::Unresolvable, SocketError, SystemCallError,
        Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, IOError => error
      raise Unreachable, error.message
    end

    # Development lists communities on localhost, which the guard rightly refuses.
    def address_for(host)
      RestrictedHTTP::PrivateNetworkGuard.resolve_public_ip!(host) unless RemoteWorkspace.allow_private_networks
    end

    def read_capped(response, max_size)
      raise Unreachable, "Response too large" if response.content_length.to_i > max_size

      String.new.tap do |body|
        response.read_body do |chunk|
          body << chunk
          raise Unreachable, "Response too large" if body.bytesize > max_size
        end
      end
    end

    def parse_manifest(origin, body)
      json = JSON.parse(body)
      raise NotSabha unless json.is_a?(Hash) && json["protocol_major"].is_a?(Integer)
      raise UnsupportedProtocol unless json["protocol_major"] == Sabha::PROTOCOL_MAJOR

      community = json["community"].is_a?(Hash) ? json["community"] : {}

      Manifest.new \
        name: name_from(community, json["product"], origin),
        logo_url: same_origin_url(community["logo_url"], origin),
        alias_origin: alias_from(community["url"], origin),
        protocol_major: json["protocol_major"],
        hub_proof: json["hub_proof"]
    rescue JSON::ParserError
      raise NotSabha
    end

    # Manifests from before the community block name only the product, which a
    # self-hosted admin usually sets to the community's name anyway.
    def name_from(community, product, origin)
      name = [ community["name"], product.try(:[], "name") ].find { it.is_a?(String) && it.strip.present? }
      name ? name.strip.truncate(100) : URI(origin).host
    end

    # Only fetch a logo from the community itself, never a third party it names
    def same_origin_url(url, origin)
      url if url.is_a?(String) && RemoteWorkspace::Origin.normalize(url) == origin
    rescue RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Origin::Hub
      nil
    end

    # A hint, never proof. An unset APP_HOST reports localhost; skip anything
    # that isn't a different, public-looking https origin.
    def alias_from(url, origin)
      return unless url.is_a?(String)

      candidate = RemoteWorkspace::Origin.normalize(url)
      host = URI(candidate).host
      candidate if candidate != origin && candidate.start_with?("https://") && host.include?(".") && !host.match?(/\A[\d.]+\z|:/)
    rescue RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Origin::Hub
      nil
    end
end
