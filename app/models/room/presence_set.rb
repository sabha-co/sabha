require "net/http"

# Who is watching a room right now, read from the anycable-go broker that holds
# their sockets.
#
# Returns a Set of user ids, or nil when the broker can't answer. Nil is not an
# empty set: empty means "nobody is here" and suppresses nothing, while nil
# means "no signal" and sends callers back to Membership#connected?.
class Room::PresenceSet
  TIMEOUT = 1.second

  # anycable-go's --api_path default, which we never override.
  API_PATH = "/api"

  # anycable-go derives its API secret from the main secret with this label
  # unless --api_secret is passed. We don't pass one, so we derive the same.
  API_SECRET_LABEL = "api-cable"

  # Not a blanket rescue: a bug in here must not disguise itself as "broker
  # down" and silently push every watching member for the rest of time.
  FETCH_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse,
    IOError, SystemCallError, SocketError, JSON::ParserError
  ].freeze

  def self.for(room) = new(room).user_ids

  def initialize(room)
    @room = room
  end

  def user_ids
    response = get
    return parse(response.body) if response.is_a?(Net::HTTPSuccess)

    # A 404 means the broker predates the HTTP API (below 1.6.9); a 401 means the
    # secret drifted. Both fail open and neither raises, so this log is the only tell.
    Rails.logger.warn "[presence] #{stream} unavailable: HTTP #{response.code}"
    nil
  rescue *FETCH_ERRORS => error
    Rails.logger.warn "[presence] #{stream} unavailable: #{error.class}: #{error.message}"
    nil
  end

  private
    # Must match PresenceChannel.broadcasting_for byte-for-byte, or we read an
    # empty set and push everyone. Tenant-scoped by the Room GID.
    def stream
      @stream ||= PresenceChannel.broadcasting_for(@room)
    end

    def get
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{api_secret}")
      end
    end

    # The API rides the broadcast host and port (--api_port defaults to the main
    # server port). Don't move this to anycable.yml: AnyCable::Config keeps only
    # its own declared attrs and drops the rest — restore_from_cache and
    # cache_ttl sit there dead today.
    def uri
      @uri ||= URI(AnyCable.config.http_broadcast_url)
        .merge("#{API_PATH}/presence/#{ERB::Util.url_encode(stream)}/users")
    end

    def api_secret
      OpenSSL::HMAC.hexdigest "SHA256", AnyCable.config.secret, API_SECRET_LABEL
    end

    # `records` is omitted entirely when the set is empty, and ids arrive as
    # strings. Anything non-numeric isn't ours, so drop it rather than coerce.
    def parse(body)
      records = JSON.parse(body)["records"] || []
      records.filter_map { |record| Integer(record["id"], exception: false) }.to_set
    end
end
