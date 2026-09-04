# frozen_string_literal: true

require_relative "../test_helper"

module Saas
  class DesktopRenderingTest < ActionDispatch::IntegrationTest
    setup do
      workspace = workspaces(:acme)
      tenant_id = workspace.external_id.to_s
      ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
      sign_in_global_identity(global_identities(:alice))
    end

    test "desktop client requests omit the in-page workspace selector" do
      workspace_get "/", workspace: workspaces(:acme), headers: { "Sabha-Desktop-Client" => "1" }

      assert_response :success
      assert_select "aside.workspace-selector", count: 0
    end

    test "browser requests still render the workspace selector" do
      workspace_get "/", workspace: workspaces(:acme)

      assert_response :success
      assert_select "aside.workspace-selector", count: 1
    end
  end
end
