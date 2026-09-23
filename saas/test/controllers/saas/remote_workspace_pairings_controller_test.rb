# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../../test/test_helpers/dns_test_helper"

module Saas
  class RemoteWorkspacePairingsControllerTest < ActionDispatch::IntegrationTest
    include DnsTestHelper

    setup do
      @alice = global_identities(:alice)
      @acme = remote_workspaces(:acme)
      sign_in_global_identity(@alice)
      stub_dns_resolution("93.184.216.34")
    end

    test "asks for the community's address" do
      get "/remote_workspace_pairings/new"

      assert_response :success
      assert_select "input[name=origin]"
    end

    test "shows the secret once, with the steps to finish" do
      post "/remote_workspace_pairings", params: { origin: "chat.acme.org" }

      assert_response :created
      pairing = @alice.remote_workspace_pairings.sole
      assert_select "input#hub_secret[value=?]", pairing.secret
      assert_select "code", text: "SABHA_HUB_SECRET"
      assert_select "form[action=?]", "/remote_workspace_pairings/#{pairing.id}", text: "Verify"

      get "/remote_workspace_pairings/#{pairing.id}"
      assert_select "input#hub_secret", count: 0
      assert_select "a", text: "Start again"
    end

    test "explains an address it can't pair" do
      post "/remote_workspace_pairings", params: { origin: "http://chat.acme.org" }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /https/
    end

    test "won't pair an address an env client answers for" do
      ENV["SSO_PROVIDER_CLIENTS"], ENV["SSO_ACME_RETURN_HOST"], ENV["SSO_ACME_SECRET"] = "acme", "chat.acme.org", "secret"

      post "/remote_workspace_pairings", params: { origin: "chat.acme.org" }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /another way/
    ensure
      %w[ SSO_PROVIDER_CLIENTS SSO_ACME_RETURN_HOST SSO_ACME_SECRET ].each { ENV.delete(it) }
    end

    test "verify switches the shortcut on" do
      pairing = @alice.pair_remote_workspace!(@acme)
      stub_manifest(hub_proof: RemoteWorkspace.pairing_proof(pairing.secret, @acme.origin))

      patch "/remote_workspace_pairings/#{pairing.id}"

      assert_redirected_to settings_path
      assert @acme.reload.pairing_active?
    end

    test "verify says what to check when the proof isn't there yet" do
      pairing = @alice.pair_remote_workspace!(@acme)
      stub_manifest({})

      patch "/remote_workspace_pairings/#{pairing.id}"

      assert_redirected_to remote_workspace_pairing_path(pairing)
      assert_match "SABHA_HUB_SECRET", flash[:alert]
      assert @acme.reload.pairing_none?
    end

    test "an expired request starts over" do
      pairing = @alice.pair_remote_workspace!(@acme)

      travel 25.hours do
        patch "/remote_workspace_pairings/#{pairing.id}"
      end

      assert_redirected_to new_remote_workspace_pairing_path(origin: @acme.origin)
    end

    test "someone else's request can't be seen or verified" do
      pairing = global_identities(:bob).pair_remote_workspace!(@acme)

      assert_raises(ActiveRecord::RecordNotFound) { get "/remote_workspace_pairings/#{pairing.id}" }
      assert_raises(ActiveRecord::RecordNotFound) { patch "/remote_workspace_pairings/#{pairing.id}" }
    end

    test "whoever paired a community can disconnect it" do
      @acme.update!(pairing_status: :active, hub_secret: "secret", paired_by: @alice)

      delete "/remote_workspaces/#{@acme.id}/connection"

      assert_redirected_to settings_path
      assert @acme.reload.pairing_revoked?
    end

    test "nobody else can" do
      @acme.update!(pairing_status: :active, hub_secret: "secret", paired_by: global_identities(:bob))

      assert_raises(ActiveRecord::RecordNotFound) { delete "/remote_workspaces/#{@acme.id}/connection" }
      assert @acme.reload.pairing_active?
    end

    test "settings list connected communities and waiting requests" do
      @acme.update!(pairing_status: :active, hub_secret: "secret", paired_by: @alice)
      @alice.pair_remote_workspace!(remote_workspaces(:club))

      get "/settings"

      assert_select "span", text: "chat.acme.org · Connected"
      assert_select "span", text: "club.example · Waiting for Verify"
      assert_select "form[action=?]", "/remote_workspaces/#{@acme.id}/connection", text: "Disconnect"
    end

    test "a member can take back their approval from settings" do
      @acme.update!(pairing_status: :active, hub_secret: "secret")
      @alice.consent_to_remote_workspace!(@acme)
      membership = remote_workspace_memberships(:alice_acme)

      get "/settings"
      assert_select "span", text: /Signs in with sabha.co/

      delete "/remote_workspace_memberships/#{membership.id}/consent"

      assert_redirected_to settings_path
      assert_not membership.reload.consented?
    end

    private
      def stub_manifest(overrides)
        body = { protocol_major: 1, community: { name: "Acme" } }.merge(overrides)
        stub_request(:get, "#{@acme.origin}/api/manifest").to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
      end
  end
end
