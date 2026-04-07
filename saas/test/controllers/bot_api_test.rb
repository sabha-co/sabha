# frozen_string_literal: true

require_relative "../test_helper"

class BotApiTest < ActionDispatch::IntegrationTest
  test "bot can post, edit, delete messages and manage boosts in SaaS mode" do
    identity = global_identities(:alice)

    with_provisioned_workspace(name: "Bot Test", creator: identity) do |workspace|
      tenant_id = workspace.external_id.to_s

      bot, room, message = ApplicationRecord.with_tenant(tenant_id) do
        bot = User.create_bot!(name: "SaaS Bot")
        room = bot.rooms.without_threads.first
        message = room.messages.create!(body: "Hello", creator: bot, client_message_id: SecureRandom.uuid)
        [ bot, room, message ]
      end

      # Post message
      workspace_post "/rooms/#{room.id}/#{bot.bot_key}/messages", workspace: workspace,
        params: "New message", headers: { "CONTENT_TYPE" => "text/plain" }
      assert_response :created

      # Edit message
      workspace_patch "/rooms/#{room.id}/#{bot.bot_key}/messages/#{message.id}", workspace: workspace,
        params: "Edited", headers: { "CONTENT_TYPE" => "text/plain" }
      assert_response :success
      assert_equal "Edited", response.parsed_body["body"]["plain"]

      # Add boost
      workspace_post "/rooms/#{room.id}/#{bot.bot_key}/messages/#{message.id}/boosts", workspace: workspace,
        params: "\u{1f389}", headers: { "CONTENT_TYPE" => "text/plain" }
      assert_response :created
      boost_id = response.parsed_body["id"]

      # Remove boost
      workspace_delete "/rooms/#{room.id}/#{bot.bot_key}/messages/#{message.id}/boosts/#{boost_id}", workspace: workspace
      assert_response :no_content

      # List members
      get "/#{workspace.external_id}/rooms/#{room.id}/#{bot.bot_key}/members"
      assert_response :success
      assert response.parsed_body.any? { |m| m["role"] == "bot" }

      # Search
      get "/#{workspace.external_id}/#{bot.bot_key}/search?q=Hello"
      assert_response :success

      # Delete message
      workspace_delete "/rooms/#{room.id}/#{bot.bot_key}/messages/#{message.id}", workspace: workspace
      assert_response :no_content
    end
  end

  test "bot key from one workspace cannot access another workspace" do
    identity = global_identities(:alice)

    with_provisioned_workspace(name: "Workspace A", creator: identity) do |ws_a|
      with_provisioned_workspace(name: "Workspace B", creator: identity) do |ws_b|
        bot = ApplicationRecord.with_tenant(ws_a.external_id.to_s) do
          User.create_bot!(name: "Bot A")
        end

        room_b = ApplicationRecord.with_tenant(ws_b.external_id.to_s) do
          Rooms::Open.first
        end

        next unless room_b

        # Bot A's key used against workspace B
        get "/#{ws_b.external_id}/rooms/#{room_b.id}/#{bot.bot_key}/members"
        assert_response :redirect
      end
    end
  end
end
