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

      headers = { "Authorization" => "Bearer #{bot.bot_key}" }

      # Post message
      workspace_post "/api/bots/rooms/#{room.id}/messages", workspace: workspace,
        params: "New message", headers: headers.merge("CONTENT_TYPE" => "text/plain")
      assert_response :created

      # Edit message (id-only)
      workspace_patch "/api/bots/messages/#{message.id}", workspace: workspace,
        params: "Edited", headers: headers.merge("CONTENT_TYPE" => "text/plain")
      assert_response :success
      assert_equal "Edited", response.parsed_body["body"]["plain"]

      # Add boost (id-only)
      workspace_post "/api/bots/messages/#{message.id}/boosts", workspace: workspace,
        params: "\u{1f389}", headers: headers.merge("CONTENT_TYPE" => "text/plain")
      assert_response :created
      boost_id = response.parsed_body["id"]

      # Remove boost (id-only)
      workspace_delete "/api/bots/messages/#{message.id}/boosts/#{boost_id}", workspace: workspace, headers: headers
      assert_response :no_content

      # List members
      get "/#{workspace.external_id}/api/bots/rooms/#{room.id}/members", headers: headers
      assert_response :success
      assert response.parsed_body.any? { |m| m["role"] == "bot" }

      # Search
      get "/#{workspace.external_id}/api/bots/search?q=Hello", headers: headers
      assert_response :success

      # Delete message (id-only)
      workspace_delete "/api/bots/messages/#{message.id}", workspace: workspace, headers: headers
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
        assert room_b, "expected workspace B to have a room to probe"

        # Bot A's key used against workspace B via bearer header
        get "/#{ws_b.external_id}/api/bots/rooms/#{room_b.id}/members",
          headers: { "Authorization" => "Bearer #{bot.bot_key}" }

        # Foreign bot key does not authenticate in workspace B: bounced to the
        # untenanted login, never served the member list.
        assert_redirected_to new_session_path(script_name: "")
      end
    end
  end
end
