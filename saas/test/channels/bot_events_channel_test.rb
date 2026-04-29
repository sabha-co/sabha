# frozen_string_literal: true

require_relative "../test_helper"

class SaasBotEventsChannelTest < ActionCable::Channel::TestCase
  include SaasTestHelper

  tests BotEventsChannel

  test "stream name is scoped to current tenant in SaaS mode" do
    with_provisioned_workspace(name: "Scoped Stream WS", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      bot = ApplicationRecord.with_tenant(tenant_id) { User.create_bot!(name: "ScopedStreamBot") }

      ApplicationRecord.with_tenant(tenant_id) do
        assert_equal "bot_events:#{tenant_id}:#{bot.id}", BotEventsChannel.stream_name_for(bot)
      end
    end
  end

  test "stream_name_for raises when tenant context is missing in SaaS mode" do
    with_provisioned_workspace(name: "Tenantless WS", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      bot = ApplicationRecord.with_tenant(tenant_id) { User.create_bot!(name: "TenantlessBot") }

      error = assert_raises(RuntimeError) do
        ApplicationRecord.without_tenant { BotEventsChannel.stream_name_for(bot) }
      end
      assert_match(/tenant context/, error.message)
    end
  end

  test "two bots with the same id in different tenants do not share a stream" do
    with_provisioned_workspace(name: "Cross Tenant A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Cross Tenant B", creator: global_identities(:bob)) do |ws_b|
        bot_a = ApplicationRecord.with_tenant(ws_a.external_id.to_s) { User.create_bot!(name: "BotA") }
        bot_b = ApplicationRecord.with_tenant(ws_b.external_id.to_s) { User.create_bot!(name: "BotB") }

        stream_a = ApplicationRecord.with_tenant(ws_a.external_id.to_s) { BotEventsChannel.stream_name_for(bot_a) }
        stream_b = ApplicationRecord.with_tenant(ws_b.external_id.to_s) { BotEventsChannel.stream_name_for(bot_b) }

        assert_not_equal stream_a, stream_b, "stream names must differ across tenants even when bot ids collide"
        assert_includes stream_a, ws_a.external_id.to_s
        assert_includes stream_b, ws_b.external_id.to_s
      end
    end
  end

  test "bot subscribed in one workspace does not also subscribe to another workspace's stream" do
    with_provisioned_workspace(name: "Subscribed WS A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Subscribed WS B", creator: global_identities(:bob)) do |ws_b|
        tenant_a = ws_a.external_id.to_s
        tenant_b = ws_b.external_id.to_s

        bot_a = ApplicationRecord.with_tenant(tenant_a) { User.create_bot!(name: "BotA") }

        stub_connection(current_user: bot_a, current_tenant: tenant_a)
        ApplicationRecord.with_tenant(tenant_a) { subscribe }

        expected_stream = "bot_events:#{tenant_a}:#{bot_a.id}"
        foreign_stream  = "bot_events:#{tenant_b}:#{bot_a.id}"
        legacy_stream   = "bot_events:#{bot_a.id}"

        assert_has_stream expected_stream
        assert_no_streams_match foreign_stream
        assert_no_streams_match legacy_stream
      end
    end
  end

  private
    def assert_no_streams_match(name)
      assert_not subscription.streams.include?(name),
        "expected channel not to subscribe to #{name.inspect} but it did"
    end
end
