require_relative "../../test_helper"

class SaasBotEventTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "same-id bots dispatch within their tenant and queued delivery restores its originating tenant" do
    Resolv.stubs(:getaddresses).returns([ "93.184.216.34" ])

    with_provisioned_workspace(name: "Bot Event A", creator: global_identities(:alice)) do |workspace_a|
      with_provisioned_workspace(name: "Bot Event B", creator: global_identities(:bob)) do |workspace_b|
        tenant_a, tenant_b = [ workspace_a, workspace_b ].map { |workspace| workspace.external_id.to_s }
        bot_id = 424242
        records = [ tenant_a, tenant_b ].map do |tenant|
          ApplicationRecord.with_tenant(tenant) do
            bot = User.create_bot!(id: bot_id, name: "Bot #{tenant}", webhook_url: "https://example.com/hook/#{tenant}")
            room = bot.rooms.without_threads.first
            message = room.messages.create!(creator: bot, body: "Message from #{tenant}")
            [ bot, room, message ]
          end
        end

        records.each_with_index do |(bot, room, message), index|
          tenant, foreign_tenant = index.zero? ? [ tenant_a, tenant_b ] : [ tenant_b, tenant_a ]
          base_url = "https://chat.example.test/#{tenant}"
          payload = nil

          ApplicationRecord.with_tenant(tenant) do
            assert_no_broadcasts "bot_events:#{foreign_tenant}:#{bot_id}" do
              assert_broadcasts "bot_events:#{tenant}:#{bot_id}", 1 do
                assert_enqueued_jobs 1, only: Bot::WebhookJob do
                  Bot::Event.new(message, :updated, base_url: base_url).dispatch
                end
              end
            end
            payload = JSON.parse(broadcasts("bot_events:#{tenant}:#{bot_id}").last)
            assert_equal base_url + Rails.application.routes.url_helpers.room_at_message_path(room, message), payload.dig("message", "url")
            assert_equal base_url + Rails.application.routes.url_helpers.api_bots_room_messages_path(room), payload.dig("room", "messages_url")
            assert_equal bot.id, payload.dig("user", "id")
          end

          job = enqueued_jobs.select { |entry| entry[:job] == Bot::WebhookJob }.last
          assert_equal tenant, job["tenant"]
          WebMock.stub_request(:post, "https://example.com/hook/#{tenant}")
            .with(body: payload.to_json).to_return(status: 200)

          # A worker may switch tenants; request-scoped shard locks must not be
          # carried into this simulation of job execution.
          ApplicationRecord.with_tenant(foreign_tenant, prohibit_shard_swapping: false) do
            perform_enqueued_jobs(only: Bot::WebhookJob)
            assert_equal foreign_tenant, ApplicationRecord.current_tenant
          end
          assert_requested :post, "https://example.com/hook/#{tenant}", times: 1
        end
      end
    end
  end
end
