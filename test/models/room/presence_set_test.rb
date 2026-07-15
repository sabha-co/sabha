require "test_helper"

class Room::PresenceSetTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:designers)
  end

  test "returns present user ids as an integer Set" do
    stub_presence records: [ { id: users(:david).id.to_s }, { id: users(:jason).id.to_s } ]

    assert_equal Set[users(:david).id, users(:jason).id], Room::PresenceSet.for(@room)
  end

  test "an empty presence set is an empty Set, not unavailable" do
    stub_presence_body({ type: "info", total: 0 }.to_json)

    presence = Room::PresenceSet.for(@room)

    assert_equal Set.new, presence
    refute_nil presence, "an empty room must suppress nothing, not fall back to the DB"
  end

  test "ignores presence ids that aren't ours" do
    stub_presence records: [ { id: users(:david).id.to_s }, { id: "anonymous-viewer" } ]

    assert_equal Set[users(:david).id], Room::PresenceSet.for(@room)
  end

  test "requests the stream PresenceChannel broadcasts on, url-encoded" do
    stream = PresenceChannel.broadcasting_for(@room)
    request = stub_presence(records: [])

    Room::PresenceSet.for(@room)

    assert_requested request
    assert_includes stream, ":", "guards the encoding assertion below staying meaningful"
    assert_equal "/api/presence/#{ERB::Util.url_encode(stream)}/users", URI(presence_url).path
  end

  test "authenticates with the secret derived from the AnyCable secret" do
    expected = OpenSSL::HMAC.hexdigest("SHA256", AnyCable.config.secret, "api-cable")
    request = stub_presence(records: []).with(headers: { "Authorization" => "Bearer #{expected}" })

    Room::PresenceSet.for(@room)

    assert_requested request
  end

  # Every one of these must read as "no signal" so push gating falls back to the
  # DB. Returning an empty Set instead would mean "nobody is watching" and push
  # the whole room.
  test "an unanswerable broker is unavailable, never an empty set" do
    { "not found" => 404, "presence unsupported by broker" => 501,
      "unauthorized" => 401, "server error" => 500 }.each do |reason, status|
      WebMock.reset!
      stub_presence_status status

      assert_nil Room::PresenceSet.for(@room), "#{reason} (#{status}) must be unavailable"
    end
  end

  test "a broker that times out or refuses the connection is unavailable" do
    [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError ].each do |error|
      WebMock.reset!
      stub_presence_request.to_raise(error)

      assert_nil Room::PresenceSet.for(@room), "#{error} must not escape"
    end
  end

  test "a broker answering with garbage is unavailable" do
    stub_presence_body "<html>502 Bad Gateway</html>"

    assert_nil Room::PresenceSet.for(@room)
  end

  private
    def presence_url
      stream = PresenceChannel.broadcasting_for(@room)
      URI(AnyCable.config.http_broadcast_url)
        .merge("/api/presence/#{ERB::Util.url_encode(stream)}/users").to_s
    end

    def stub_presence_request
      stub_request(:get, presence_url)
    end

    def stub_presence(records:)
      stub_presence_body({ type: "info", total: records.size, records: records }.to_json)
    end

    def stub_presence_body(body)
      stub_presence_request.to_return(status: 200, body: body)
    end

    def stub_presence_status(status)
      stub_presence_request.to_return(status: status, body: "")
    end
end
