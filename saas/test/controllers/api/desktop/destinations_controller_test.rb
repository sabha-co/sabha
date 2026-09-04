# frozen_string_literal: true

require_relative "../../../test_helper"

module Saas
  class API::Desktop::DestinationsSaasControllerTest < ActionDispatch::IntegrationTest
    setup do
      [ workspaces(:acme), workspaces(:shared), workspaces(:suspended) ].each do |workspace|
        tenant_id = workspace.external_id.to_s
        ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
      end
      sign_in_global_identity(global_identities(:alice))
    end

    test "returns ordered active workspace peers with tenant cable paths" do
      get "/api/desktop/destinations", headers: desktop_headers

      assert_response :success
      body = JSON.parse(response.body)
      ids = body["destinations"].map { |d| d["id"] }
      assert_equal [ "1000001", "1000003" ], ids
      assert_equal "/api/cable?wid=1000001", body["destinations"].first["cable_path"]
      refute_includes ids, "1000004"
    end

    test "is unauthorized without a global session" do
      reset!

      get "/api/desktop/destinations", headers: desktop_headers

      assert_response :unauthorized
    end

    private
      def desktop_headers
        { "Sabha-Desktop-Protocol-Major" => "1" }
      end
  end
end
