# frozen_string_literal: true

require_relative "../../test_helper"

# Presence gating decides who gets a push, so a stream name that collided
# across workspaces would leak one tenant's watchers into another's push
# decisions. Nothing in anycable-go enforces that separation — one secret
# authorizes every API call — so it holds only because the Channel GID carries the
# tenant. These pin that.
class Channel::PresenceSetTenancyTest < ActiveSupport::TestCase
  setup do
    @tenant_a = workspaces(:acme).external_id.to_s
    @tenant_b = workspaces(:widgets).external_id.to_s

    [ @tenant_a, @tenant_b ].each do |tenant|
      ApplicationRecord.create_tenant(tenant) unless ApplicationRecord.tenant_exist?(tenant)
    end
  end

  test "the same channel id in two workspaces produces different presence streams" do
    channel_a, stream_a = ApplicationRecord.with_tenant(@tenant_a) { channel_and_stream }
    channel_b, stream_b = ApplicationRecord.with_tenant(@tenant_b) { channel_and_stream }

    assert_equal channel_a, channel_b,
      "this test is only meaningful when the ids collide — tenant DBs are separate, so they should"
    refute_equal stream_a, stream_b,
      "same channel id in different workspaces must not share a presence stream"
  end

  test "a fetch for one workspace never returns another workspace's users" do
    stream_b = ApplicationRecord.with_tenant(@tenant_b) { channel_and_stream.last }

    ApplicationRecord.with_tenant(@tenant_a) do
      channel = find_or_create_channel
      stub_request(:get, presence_url_for(PresenceChannel.broadcasting_for(channel)))
        .to_return(status: 200, body: { type: "info", total: 1, records: [ { id: "1" } ] }.to_json)

      # Tenant B's stream is stubbed to answer with a different user. If the
      # stream name were tenant-blind, this is the response we'd wrongly get.
      stub_request(:get, presence_url_for(stream_b))
        .to_return(status: 200, body: { type: "info", total: 1, records: [ { id: "999" } ] }.to_json)

      assert_equal Set[1], Channel::PresenceSet.for(channel)
    end
  end

  # The stream names differing is necessary but not sufficient — this is the
  # thing that would actually hurt: one workspace's watchers suppressing another
  # workspace's pushes.
  test "presence in one workspace never gates push in another" do
    ApplicationRecord.with_tenant(@tenant_b) do
      channel = find_or_create_channel
      watching channel, 1 # user id 1 is watching over in tenant B
    end

    ApplicationRecord.with_tenant(@tenant_a) do
      channel = find_or_create_channel
      creator = User.find_or_create_by!(email_address: "creator@example.com") do |user|
        user.name = "Creator"
        user.role = :member
        user.verified_at = Time.current
      end
      channel.memberships.find_or_create_by!(user: creator)

      assert_nil Channel::PresenceSet.for(channel).find { |id| id == 1 },
        "tenant A must read its own (empty) presence set, not tenant B's watcher"
    end
  end

  private
    def channel_and_stream
      channel = find_or_create_channel
      [ channel.id, PresenceChannel.broadcasting_for(channel) ]
    end

    def find_or_create_channel
      creator = User.find_or_create_by!(email_address: "presence@example.com") do |user|
        user.name = "Presence Tester"
        user.role = :administrator
        user.verified_at = Time.current
      end

      Channels::Open.find_or_create_by!(name: "Presence Channel") do |channel|
        channel.slug = "presence-channel"
        channel.creator = creator
      end
    end

    def presence_url_for(stream)
      URI(AnyCable.config.http_broadcast_url)
        .merge("/api/presence/#{ERB::Util.url_encode(stream)}/users").to_s
    end
end
