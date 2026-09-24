# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../../test/test_helpers/dns_test_helper"

module Saas
  class RemoteWorkspacesControllerTest < ActionDispatch::IntegrationTest
    include DnsTestHelper

    ORIGIN = "https://new.example"

    setup do
      @alice = global_identities(:alice)
      sign_in_global_identity(@alice)
      stub_dns_resolution("93.184.216.34")
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200,
        body: { protocol_major: 1, workspace: { name: "New" } }.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "asks for an address" do
      get "/remote_workspaces/new"

      assert_response :success
      assert_select "input[name=origin]"
    end

    test "shows the workspace's name and address to confirm" do
      get "/remote_workspaces/new", params: { origin: "new.example/rooms/3", source: "prompt" }

      assert_response :success
      assert_select "strong", "New"
      assert_select "span", "new.example"
      assert_select "input[name=origin][value=?]", ORIGIN
      assert_select "input[name=source][value=prompt]"
    end

    test "says a workspace is already in the list instead of offering to add it" do
      acme = remote_workspaces(:acme)

      get "/remote_workspaces/new", params: { origin: acme.origin }

      assert_select "h1", "Already in your list"
      assert_select "a[href=?]", acme.origin, text: "Open Acme"
      assert_select "form[action='/remote_workspace_pairing_requests'] input[name=remote_workspace_id][value=?]", acme.id.to_s
      assert_select "form[action='/remote_workspaces']", count: 0
    end

    test "offers to show a hidden workspace again" do
      acme = remote_workspaces(:acme)
      remote_workspace_memberships(:alice_acme).update!(hidden: true)

      get "/remote_workspaces/new", params: { origin: acme.origin }

      assert_select "form[action='/remote_workspaces'] button", "Show in sidebar"
    end

    test "offers the address a workspace calls itself" do
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200,
        body: { protocol_major: 1, workspace: { name: "New", url: "https://chat.new.example" } }.to_json)

      get "/remote_workspaces/new", params: { origin: ORIGIN }

      assert_select "a[href=?]", new_remote_workspace_path(origin: "https://chat.new.example"), text: "Add that address instead"
    end

    test "a workspace claiming a listed address is still a different entry" do
      acme = remote_workspaces(:acme)
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200,
        body: { protocol_major: 1, workspace: { name: "New", url: acme.origin } }.to_json)

      get "/remote_workspaces/new", params: { origin: ORIGIN }
      assert_select "h1", text: "Already in your list", count: 0
      assert_select "form[action='/remote_workspaces'] button", "Add to my list"

      assert_difference -> { @alice.remote_workspace_memberships.count }, 1 do
        post "/remote_workspaces", params: { origin: ORIGIN }
      end
      assert @alice.remote_workspace_memberships.joins(:remote_workspace).exists?(remote_workspaces: { origin: acme.origin })
    end

    test "explains why an address can't be added" do
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 404)

      get "/remote_workspaces/new", params: { origin: ORIGIN }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", "That isn't a Sabha workspace, or its Sabha is too old."
      assert_select "input[name=origin][value=?]", ORIGIN
    end

    test "refuses sabha.co itself, whatever address reaches it" do
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200,
        body: { protocol_major: 1, product: { name: "Sabha" }, multi_tenant: true }.to_json)

      get "/remote_workspaces/new", params: { origin: ORIGIN }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", "That's sabha.co, not a self-hosted workspace."
    end

    test "explains an address that isn't one" do
      get "/remote_workspaces/new", params: { origin: "http://new.example" }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", "Use an https:// address."
    end

    test "adding a workspace puts it in the person's list" do
      assert_difference -> { @alice.remote_workspace_memberships.count }, 1 do
        post "/remote_workspaces", params: { origin: "New.Example" }
      end

      assert_redirected_to settings_path
      membership = @alice.remote_workspace_memberships.joins(:remote_workspace).find_by!(remote_workspaces: { origin: ORIGIN })
      assert_equal "New", membership.remote_workspace.name
      assert_equal "added", membership.source
    end

    test "an admin who ticks I run this workspace gets a secret, shown once" do
      get "/remote_workspaces/new", params: { origin: ORIGIN }
      assert_select "input[type=checkbox][name=pair][value='1']"

      post "/remote_workspaces", params: { origin: ORIGIN, pair: "1" }

      assert_response :created
      pairing = @alice.remote_workspace_pairing_requests.sole
      assert_equal ORIGIN, pairing.remote_workspace.origin
      assert @alice.remote_workspace_memberships.exists?(remote_workspace: pairing.remote_workspace)
      assert_select "input#hub_secret[value=?]", pairing.secret
      assert_select "form[action=?]", "/remote_workspace_pairing_requests/#{pairing.id}", text: "Verify"
    end

    test "a member who leaves it unticked only lists the workspace" do
      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_redirected_to settings_path
      assert_empty @alice.remote_workspace_pairing_requests
    end

    test "won't pair an address an env client answers for, and doesn't list it either" do
      ENV["SSO_PROVIDER_CLIENTS"], ENV["SSO_NEW_RETURN_HOST"], ENV["SSO_NEW_SECRET"] = "new", "new.example", "secret"

      assert_no_difference -> { @alice.remote_workspace_memberships.count } do
        post "/remote_workspaces", params: { origin: ORIGIN, pair: "1" }
      end

      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /another way/
    ensure
      %w[ SSO_PROVIDER_CLIENTS SSO_NEW_RETURN_HOST SSO_NEW_SECRET ].each { ENV.delete(it) }
    end

    test "records that an entry came from a workspace's prompt" do
      post "/remote_workspaces", params: { origin: ORIGIN, source: "prompt" }

      assert_equal "prompt", @alice.remote_workspace_memberships.last.source
    end

    test "sends a sabha.co workspace address to that workspace" do
      post "/remote_workspaces", params: { origin: "#{Branding.app_host}/1000003" }

      assert_redirected_to "/1000003"
      assert_equal 1, @alice.remote_workspace_memberships.count
    end

    test "says so when the list is full" do
      fill_remote_workspace_list @alice

      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_redirected_to settings_path
      assert_match "list is full", flash[:alert]
    end

    test "limits look-ups per person" do
      20.times { post "/remote_workspaces", params: { origin: ORIGIN } }
      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_match "Too many look-ups", flash[:alert]
    end

    test "opening the empty form isn't a look-up, and look-ups don't use up adds" do
      40.times { get "/remote_workspaces/new" }
      assert_response :success

      30.times { get "/remote_workspaces/new", params: { origin: ORIGIN } }
      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_redirected_to settings_path
      assert_nil flash[:alert]
    end

    test "requires sign-in" do
      delete session_path

      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_redirected_to new_session_path
    end
  end
end
