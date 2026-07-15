# frozen_string_literal: true

require_relative "../../test_helper"

# R3: presence gating decides who gets a push, so a stream name that collided
# across workspaces would leak one tenant's watchers into another's push
# decisions. Nothing in anycable-go enforces that separation — one secret
# authorizes every API call — so it holds only because the Room GID carries the
# tenant. These pin that.
class Room::PresenceSetTenancyTest < ActiveSupport::TestCase
  setup do
    @tenant_a = workspaces(:acme).external_id.to_s
    @tenant_b = workspaces(:widgets).external_id.to_s

    [ @tenant_a, @tenant_b ].each do |tenant|
      ApplicationRecord.create_tenant(tenant) unless ApplicationRecord.tenant_exist?(tenant)
    end
  end

  test "the same room id in two workspaces produces different presence streams" do
    room_a, stream_a = ApplicationRecord.with_tenant(@tenant_a) { room_and_stream }
    room_b, stream_b = ApplicationRecord.with_tenant(@tenant_b) { room_and_stream }

    assert_equal room_a, room_b,
      "this test is only meaningful when the ids collide — tenant DBs are separate, so they should"
    refute_equal stream_a, stream_b,
      "same room id in different workspaces must not share a presence stream"
  end

  test "a fetch for one workspace never returns another workspace's users" do
    stream_b = ApplicationRecord.with_tenant(@tenant_b) { room_and_stream.last }

    ApplicationRecord.with_tenant(@tenant_a) do
      room = find_or_create_room
      stub_request(:get, presence_url_for(PresenceChannel.broadcasting_for(room)))
        .to_return(status: 200, body: { type: "info", total: 1, records: [ { id: "1" } ] }.to_json)

      # Tenant B's stream is stubbed to answer with a different user. If the
      # stream name were tenant-blind, this is the response we'd wrongly get.
      stub_request(:get, presence_url_for(stream_b))
        .to_return(status: 200, body: { type: "info", total: 1, records: [ { id: "999" } ] }.to_json)

      assert_equal Set[1], Room::PresenceSet.for(room)
    end
  end

  private
    def room_and_stream
      room = find_or_create_room
      [ room.id, PresenceChannel.broadcasting_for(room) ]
    end

    def find_or_create_room
      creator = User.find_or_create_by!(email_address: "presence@example.com") do |user|
        user.name = "Presence Tester"
        user.role = :administrator
        user.verified_at = Time.current
      end

      Rooms::Open.find_or_create_by!(name: "Presence Room") do |room|
        room.slug = "presence-room"
        room.creator = creator
      end
    end

    def presence_url_for(stream)
      URI(AnyCable.config.http_broadcast_url)
        .merge("/api/presence/#{ERB::Util.url_encode(stream)}/users").to_s
    end
end
