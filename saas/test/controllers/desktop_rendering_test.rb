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

    test "desktop client requests still render the workspace selector" do
      workspace_get "/", workspace: workspaces(:acme), headers: { "Sabha-Desktop-Client" => "1" }

      assert_response :success
      assert_select "aside.workspace-selector", count: 1
    end

    test "browser requests still render the workspace selector" do
      workspace_get "/", workspace: workspaces(:acme)

      assert_response :success
      assert_select "aside.workspace-selector", count: 1
    end

    test "desktop client requests omit webpush enrollment ui" do
      workspace = workspaces(:acme)
      tenant_id = workspace.external_id.to_s

      ApplicationRecord.with_tenant(tenant_id) do
        Account.find_or_create_by!(singleton_guard: 0) { |a| a.name = workspace.name }
      end
      workspace_memberships(:alice_acme).create_user!

      workspace_get "/users/me/sidebar", workspace: workspace, headers: { "Sabha-Desktop-Client" => "1" }

      assert_response :success
      assert_select "#notification_bell_container", count: 0
    end
  end
end
