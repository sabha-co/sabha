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

    test "a new secret for a workspace in the list is shown once, with the steps to finish" do
      post "/remote_workspace_pairings", params: { remote_workspace_id: @acme.id }

      assert_response :created
      pairing = @alice.remote_workspace_pairings.sole
      assert_select "input#hub_secret[value=?]", pairing.secret
      assert_select "code", text: "SABHA_HUB_SECRET"
      assert_select "form[action=?]", "/remote_workspace_pairings/#{pairing.id}", text: "Verify"

      get "/remote_workspace_pairings/#{pairing.id}"
      assert_select "input#hub_secret", count: 0
      assert_select "form[action='/remote_workspace_pairings'] input[name=remote_workspace_id][value=?]", @acme.id.to_s
    end

    test "only workspaces in the person's list can be paired" do
      assert_raises(ActiveRecord::RecordNotFound) do
        post "/remote_workspace_pairings", params: { remote_workspace_id: remote_workspaces(:club).id }
      end
    end

    test "won't pair an address an env client answers for" do
      ENV["SSO_PROVIDER_CLIENTS"], ENV["SSO_ACME_RETURN_HOST"], ENV["SSO_ACME_SECRET"] = "acme", "chat.acme.org", "secret"

      post "/remote_workspace_pairings", params: { remote_workspace_id: @acme.id }

      assert_redirected_to settings_path
      assert_match "another way", flash[:alert]
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

      assert_redirected_to settings_path
      assert_match "new secret", flash[:alert]
    end

    test "someone else's request can't be seen or verified" do
      pairing = global_identities(:bob).pair_remote_workspace!(@acme)

      assert_raises(ActiveRecord::RecordNotFound) { get "/remote_workspace_pairings/#{pairing.id}" }
      assert_raises(ActiveRecord::RecordNotFound) { patch "/remote_workspace_pairings/#{pairing.id}" }
    end

    test "whoever paired a workspace can disconnect it" do
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

    test "settings offers Verify on a waiting workspace and the pairer's actions on a connected one" do
      @acme.update!(pairing_status: :active, hub_secret: "secret", paired_by: @alice)
      club = @alice.list_remote_workspace!(remote_workspaces(:club), source: :added).remote_workspace
      pairing = @alice.pair_remote_workspace!(club)

      get "/settings"

      assert_select "a[href=?]", "/remote_workspace_pairings/#{pairing.id}", text: "Verify"
      assert_select ".list-tag--positive", text: "Continue with sabha.co"
      assert_select "form[action=?]", "/remote_workspaces/#{@acme.id}/connection", text: "Disconnect from sabha.co"
      assert_select "form[action='/remote_workspace_pairings']", text: "Get a new secret"
      assert_select "form[action='/remote_workspace_pairings']", text: "Set up Continue with sabha.co", count: 0
    end

    test "settings offers setting up the shortcut on a workspace nobody has paired" do
      get "/settings"

      assert_select "form[action='/remote_workspace_pairings'] input[name=remote_workspace_id][value=?]", @acme.id.to_s
      assert_select "form[action='/remote_workspace_pairings']", text: "Set up Continue with sabha.co"
    end

    test "a member can take back their approval from settings" do
      @acme.update!(pairing_status: :active, hub_secret: "secret")
      @alice.consent_to_remote_workspace!(@acme)
      membership = remote_workspace_memberships(:alice_acme)

      get "/settings"
      assert_select ".list-tag", text: "You sign in with sabha.co"
      assert_select "form[action=?]", "/remote_workspace_memberships/#{membership.id}/consent", text: "Stop signing in with sabha.co"

      delete "/remote_workspace_memberships/#{membership.id}/consent"

      assert_redirected_to settings_path
      assert_not membership.reload.consented?
    end

    private
      def stub_manifest(overrides)
        body = { protocol_major: 1, workspace: { name: "Acme" } }.merge(overrides)
        stub_request(:get, "#{@acme.origin}/api/manifest").to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
      end
  end
end
