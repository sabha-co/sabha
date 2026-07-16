# Push gating asks anycable-go who is watching a room (Room::PresenceSet), so
# every message dispatch now makes an HTTP call. Left unstubbed, tests would hit
# a real broker whenever one happens to be running on 8080 and otherwise fall
# into the connection-refused path — nondeterministic either way, and the
# fallback is the degraded branch rather than the one production takes.
#
# So the default here is the production-shaped one: broker reachable, nobody
# watching. Tests say who is watching with `watching`, and exercise the DB
# fallback deliberately with `presence_broker_unavailable`.
module PresenceTestHelper
  extend ActiveSupport::Concern

  PRESENCE_URL_PATTERN = %r{/api/presence/.+/users\z}

  included do
    setup { stub_empty_presence }
  end

  # Put users in a room's presence set, as anycable-go would report them.
  def watching(room, *users)
    records = users.flatten.map { |user| { id: (user.try(:id) || user).to_s } }

    stub_request(:get, presence_url_for(room))
      .to_return(status: 200, body: { type: "info", total: records.size, records: records }.to_json)
  end

  # anycable-go can't answer, so gating falls back to the connected_at column.
  def presence_broker_unavailable
    stub_request(:get, PRESENCE_URL_PATTERN).to_timeout
  end

  private
    # `records` is omitted when the set is empty, exactly as anycable-go sends it.
    def stub_empty_presence
      stub_request(:get, PRESENCE_URL_PATTERN)
        .to_return(status: 200, body: { type: "info", total: 0 }.to_json)
    end

    def presence_url_for(room)
      stream = PresenceChannel.broadcasting_for(room)
      URI(AnyCable.config.http_broadcast_url)
        .merge("/api/presence/#{ERB::Util.url_encode(stream)}/users").to_s
    end
end
