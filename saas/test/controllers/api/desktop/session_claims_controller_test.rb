# frozen_string_literal: true

require_relative "../../../test_helper"

module Saas
  class API::Desktop::SessionClaimsSaasControllerTest < ActionDispatch::IntegrationTest
    test "redeems a valid global claim once and establishes a global session" do
      identity = global_identities(:alice)
      claim = Desktop::GlobalSessionClaim.issue!(
        global_identity: identity,
        nonce: "saas-nonce",
        origin: "https://www.example.com",
        return_path: "/workspaces"
      )

      post "/api/desktop/session_claim",
        params: { token: claim.raw_token, nonce: "saas-nonce", origin: "https://www.example.com" },
        headers: desktop_headers

      assert_response :success
      assert_equal "/workspaces", JSON.parse(response.body)["return_path"]
      assert cookies[:global_session_token].present?
      assert claim.reload.used?
    end

    test "rejects a replayed global claim" do
      identity = global_identities(:alice)
      claim = Desktop::GlobalSessionClaim.issue!(
        global_identity: identity,
        nonce: "replay-nonce",
        origin: "https://www.example.com",
        return_path: "/"
      )
      params = { token: claim.raw_token, nonce: "replay-nonce", origin: "https://www.example.com" }

      post "/api/desktop/session_claim", params: params, headers: desktop_headers
      assert_response :success

      post "/api/desktop/session_claim", params: params, headers: desktop_headers
      assert_response :forbidden
    end

    private
      def desktop_headers
        { "Sabha-Desktop-Protocol-Major" => "1", "Sabha-Desktop-Client" => "1" }
      end
  end
end
