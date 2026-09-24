# frozen_string_literal: true

require_relative "../../../test_helper"

module Saas
  module Platform
    class RemoteWorkspacesControllerTest < ActionDispatch::IntegrationTest
      TOKEN = "platform-token"

      setup do
        @original_token = ENV["SABHA_PLATFORM_TOKEN"]
        ENV["SABHA_PLATFORM_TOKEN"] = TOKEN
      end

      teardown do
        @original_token ? ENV["SABHA_PLATFORM_TOKEN"] = @original_token : ENV.delete("SABHA_PLATFORM_TOKEN")
      end

      test "pairs a new droplet and lists it for its owner" do
        assert_difference -> { RemoteWorkspace.count }, +1 do
          post "/api/platform/remote_workspaces", params: { origin: "https://Rust.sabha.co", name: "Rust", owner_email: "Charlie@example.com" }, headers: auth
        end

        assert_response :created
        body = response.parsed_body
        remote_workspace = RemoteWorkspace.find_by!(origin: "https://rust.sabha.co")
        assert_equal "https://rust.sabha.co", body["origin"]
        assert_equal remote_workspace.secret, body["secret"]
        assert body["listed"]
        assert remote_workspace.pairing_active?
        assert remote_workspace.paired_via_sabha_cloud?
        assert global_identities(:charlie).remote_workspace_memberships.find_by!(remote_workspace: remote_workspace).sabha_cloud?
      end

      test "every deploy gets the secret the droplet already runs with" do
        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust" }, headers: auth
        first = response.parsed_body["secret"]

        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust" }, headers: auth

        assert_equal first, response.parsed_body["secret"]
      end

      test "takes over a workspace its owner paired by hand" do
        acme = remote_workspaces(:acme)
        acme.update!(pairing_status: :active, paired_via: :self_serve, secret: "hand-made")

        post "/api/platform/remote_workspaces", params: { origin: acme.origin, name: "Acme" }, headers: auth

        assert_not_equal "hand-made", response.parsed_body["secret"]
        assert acme.reload.paired_via_sabha_cloud?
      end

      test "an owner with a full list still gets a paired droplet" do
        fill_remote_workspace_list global_identities(:alice)

        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust", owner_email: global_identities(:alice).email_address }, headers: auth

        assert_response :created
        assert RemoteWorkspace.find_by!(origin: "https://rust.sabha.co").pairing_active?
        assert_equal false, response.parsed_body["listed"]
      end

      test "an unknown owner still gets a paired droplet" do
        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust", owner_email: "nobody@example.com" }, headers: auth

        assert_response :created
        assert_equal false, response.parsed_body["listed"]
      end

      test "refuses sabha.co itself and anything that isn't an address" do
        post "/api/platform/remote_workspaces", params: { origin: "not an address", name: "Rust" }, headers: auth

        assert_response :unprocessable_entity
      end

      test "disconnects a destroyed droplet and leaves its owner's entry" do
        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust", owner_email: "charlie@example.com" }, headers: auth

        delete "/api/platform/remote_workspaces/rust.sabha.co", headers: auth

        assert_response :no_content
        remote_workspace = RemoteWorkspace.find_by!(origin: "https://rust.sabha.co")
        assert remote_workspace.pairing_disconnected?
        assert global_identities(:charlie).remote_workspace_memberships.exists?(remote_workspace: remote_workspace)
      end

      test "a droplet it never paired is not found" do
        delete "/api/platform/remote_workspaces/gone.sabha.co", headers: auth

        assert_response :not_found
      end

      test "needs the platform token" do
        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust" }, headers: { "Authorization" => "Bearer wrong" }
        assert_response :unauthorized

        ENV.delete("SABHA_PLATFORM_TOKEN")
        post "/api/platform/remote_workspaces", params: { origin: "https://rust.sabha.co", name: "Rust" }, headers: { "Authorization" => "Bearer " }
        assert_response :unauthorized
        assert_not RemoteWorkspace.exists?(origin: "https://rust.sabha.co")
      end

      private
        def auth
          { "Authorization" => "Bearer #{TOKEN}" }
        end
    end
  end
end
