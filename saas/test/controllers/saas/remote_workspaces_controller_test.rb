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
        body: { protocol_major: 1, community: { name: "New" } }.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "asks for an address" do
      get "/remote_workspaces/new"

      assert_response :success
      assert_select "input[name=origin]"
    end

    test "shows the community's name and address to confirm" do
      get "/remote_workspaces/new", params: { origin: "new.example/rooms/3", source: "prompt" }

      assert_response :success
      assert_select "strong", "New"
      assert_select "span", "new.example"
      assert_select "input[name=origin][value=?]", ORIGIN
      assert_select "input[name=source][value=prompt]"
    end

    test "offers the address a community calls itself" do
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200,
        body: { protocol_major: 1, community: { name: "New", url: "https://chat.new.example" } }.to_json)

      get "/remote_workspaces/new", params: { origin: ORIGIN }

      assert_select "a[href=?]", new_remote_workspace_path(origin: "https://chat.new.example"), text: "Add that address instead"
    end

    test "explains why an address can't be added" do
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 404)

      get "/remote_workspaces/new", params: { origin: ORIGIN }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", /isn't a Sabha community/
      assert_select "input[name=origin][value=?]", ORIGIN
    end

    test "explains an address that isn't one" do
      get "/remote_workspaces/new", params: { origin: "http://new.example" }

      assert_response :unprocessable_entity
      assert_select "[role=alert]", "Use an https:// address."
    end

    test "adding a community puts it in the person's list" do
      assert_difference -> { @alice.remote_workspace_memberships.count }, 1 do
        post "/remote_workspaces", params: { origin: "New.Example" }
      end

      assert_redirected_to settings_path
      membership = @alice.remote_workspace_memberships.joins(:remote_workspace).find_by!(remote_workspaces: { origin: ORIGIN })
      assert_equal "New", membership.remote_workspace.name
      assert_equal "added", membership.source
    end

    test "records that an entry came from a community's prompt" do
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

    test "requires sign-in" do
      delete session_path

      post "/remote_workspaces", params: { origin: ORIGIN }

      assert_redirected_to new_session_path
    end
  end
end
