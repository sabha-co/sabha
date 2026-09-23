# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class API::DestinationsSaasControllerTest < ActionDispatch::IntegrationTest
    setup do
      [ workspaces(:acme), workspaces(:shared), workspaces(:suspended) ].each do |workspace|
        tenant_id = workspace.external_id.to_s
        ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
      end
      sign_in_global_identity(global_identities(:alice))
    end

    test "returns ordered active workspace peers with tenant cable paths" do
      get "/api/destinations", headers: protocol_headers

      assert_response :success
      body = JSON.parse(response.body)
      ids = body["peers"].map { |d| d["id"] }
      assert_equal [ "1000001", "1000003" ], ids
      assert_includes body["peers"].first["cable_url"], "/api/cable?wid=1000001"
      refute_includes ids, "1000004"
    end

    test "is unauthorized without a global session" do
      reset!

      get "/api/destinations", headers: protocol_headers

      assert_response :unauthorized
    end

    test "lists self-hosted communities separately, in selector order, without hidden ones" do
      alice = global_identities(:alice)
      acme = remote_workspace_memberships(:alice_acme)
      club = alice.list_remote_workspace!(remote_workspaces(:club), source: :added)
      alice.list_remote_workspace!(RemoteWorkspace.create!(origin: "https://hidden.example", name: "Hidden"), source: :added).update!(hidden: true)
      alice.reorder_switcher([ "remote:#{club.id}", "1000001", "remote:#{acme.id}", "1000003" ])

      get "/api/destinations", headers: protocol_headers

      body = JSON.parse(response.body)
      assert_equal [ "1000001", "1000003" ], body["peers"].map { it["id"] }
      assert_equal [ "https://club.example", "https://chat.acme.org" ], body["remote_peers"].map { it["origin"] }
      assert body["remote_peers"].first["unreachable"]
      assert_nil body["remote_peers"].first["logo_url"]
      assert_equal "http://www.example.com/remote_workspaces/#{acme.remote_workspace_id}/logo", body["remote_peers"].last["logo_url"]
    end

    test "says which communities offer Continue with sabha.co" do
      remote_workspaces(:acme).update!(pairing_status: :active, hub_secret: "secret")

      get "/api/destinations", headers: protocol_headers

      assert_equal [ true ], JSON.parse(response.body)["remote_peers"].map { it["shortcut"] }
    end

    private
      def protocol_headers
        { "Sabha-Protocol-Major" => "1" }
      end
  end
end
