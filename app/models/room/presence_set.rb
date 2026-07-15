require "net/http"

# Who is actually watching a room right now, read from anycable-go.
#
# anycable-go terminates every WebSocket, so its broker already holds the
# presence set that `PresenceChannel` joins. Asking it costs one HTTP call per
# dispatch instead of a `connected_at` column that every open tab has to keep
# warm with timed writes.
#
# Returns a Set of user ids, or nil when the broker can't answer. Nil is not an
# empty set: an empty set is a truthful "nobody is here" and suppresses nothing,
# while nil means "no signal" and sends callers back to the DB (see
# Membership::Connectable#connected?). Failing open matters more than precision
# here — a missed push is worse than a redundant one.
class Room::PresenceSet
  TIMEOUT = 1.second

  # anycable-go's --api_path default. We never pass --api_path, so this tracks it.
  API_PATH = "/api"

  # anycable-go derives the API secret from its main secret with this label
  # unless --api_secret is set explicitly. We don't set it, so we derive the
  # same value rather than carrying a second secret around.
  API_SECRET_LABEL = "api-cable"

  # Every way the broker can fail to answer. Deliberately not a blanket rescue:
  # a bug in here must not disguise itself as "broker down" and silently push
  # every watching member for the rest of time.
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

    # Worth a line rather than a silent fall-back to the DB: a 404 means the
    # broker has no API server at all (anycable-go below 1.6.9), and a 401 means
    # the secret drifted. Both fail open — every watching member gets pushed —
    # and neither raises, so this log is the only way to notice.
    Rails.logger.warn "[presence] #{stream} unavailable: HTTP #{response.code}"
    nil
  rescue *FETCH_ERRORS => error
    Rails.logger.warn "[presence] #{stream} unavailable: #{error.class}: #{error.message}"
    nil
  end

  private
    # The stream the room's presence set lives on. Must match
    # PresenceChannel.broadcasting_for byte-for-byte or we'd read an empty set
    # and push everyone. Tenant-scoped in SaaS because the Room GID carries the
    # tenant.
    def stream
      @stream ||= PresenceChannel.broadcasting_for(@room)
    end

    def get
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{api_secret}")
      end
    end

    # The API rides the same host and port as broadcasting (--api_port defaults
    # to 0, meaning "main server port"), so derive it from the one URL AnyCable
    # already declares. anycable.yml can't carry an extra key for this:
    # AnyCable::Config materializes only its own declared attrs and silently
    # drops the rest — `restore_from_cache` and `cache_ttl` sit there dead today.
    def uri
      @uri ||= URI(AnyCable.config.http_broadcast_url)
        .merge("#{API_PATH}/presence/#{ERB::Util.url_encode(stream)}/users")
    end

    def api_secret
      OpenSSL::HMAC.hexdigest "SHA256", AnyCable.config.secret, API_SECRET_LABEL
    end

    # `records` is omitted entirely when the set is empty. Ids are strings on the
    # wire; anything non-numeric isn't one of ours (nothing else joins these
    # streams today) so it's dropped rather than coerced to a bogus 0.
    def parse(body)
      records = JSON.parse(body)["records"] || []
      records.filter_map { |record| Integer(record["id"], exception: false) }.to_set
    end
end
