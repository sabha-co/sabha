# frozen_string_literal: true

require_relative "../test_helper"

class PathRewriterTest < ActionDispatch::IntegrationTest
  # Tests for PathRewriter middleware which:
  # 1. Extracts workspace ID from URL path (/1000001/rooms → tenant 1000001)
  # 2. Moves workspace prefix to SCRIPT_NAME for URL generation
  # 3. Raises TenantDoesNotExistError for non-existent tenants (converted to 404 by rescue_responses)

  setup do
    # Ensure tenant databases exist for test workspaces
    [ workspaces(:acme), workspaces(:shared) ].each do |workspace|
      tenant_id = workspace.external_id.to_s
      ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
    end
  end

  test "extracts tenant from workspace path prefix" do
    workspace = workspaces(:acme)
    sign_in_global_identity(global_identities(:alice))

    workspace_get "/", workspace: workspace

    # Should be routed to workspace root, not rejected
    assert_response :success
  end

  test "raises TenantDoesNotExistError for non-existent workspace" do
    sign_in_global_identity(global_identities(:alice))

    # Non-existent workspace ID → TenantDoesNotExistError (404 in production via rescue_responses)
    assert_raises(ActiveRecord::Tenanted::TenantDoesNotExistError) do
      get "/9999999/"
    end
  end

  test "short workspace IDs fall through to regular routing" do
    sign_in_global_identity(global_identities(:alice))

    # Workspace IDs must be 7+ digits
    # /123/ is too short - PathRewriter doesn't match it, falls through to routes
    assert_raises(ActionController::RoutingError) do
      get "/123/"
    end
  end

  test "URL helpers include workspace prefix via SCRIPT_NAME" do
    workspace = workspaces(:acme)
    sign_in_global_identity(global_identities(:alice))

    workspace_get "/", workspace: workspace

    assert_response :success
    # URLs in the response should include the workspace prefix
    # The sidebar, navigation links, etc. should all have /1000001/... paths
    assert_match %r{/#{workspace.external_id}/}, response.body,
      "Response should contain URLs with workspace prefix"
  end

  test "requests without workspace prefix go to global routes" do
    # Login page should work without workspace prefix
    get "/session/new"

    assert_response :success
  end

  test "authenticated user redirected from root to workspaces" do
    sign_in_global_identity(global_identities(:alice))

    get "/"

    # Should redirect to workspaces list or first workspace
    assert_response :redirect
  end

  test "workspace context isolated between requests" do
    sign_in_global_identity(global_identities(:alice))
    workspace_acme = workspaces(:acme)
    workspace_shared = workspaces(:shared)

    # First request to acme workspace
    workspace_get "/", workspace: workspace_acme
    assert_response :success
    # Action cable URL should reference acme workspace via query param
    assert_match %r{action-cable-url.*content="[^"]*\?wid=#{workspace_acme.external_id}"}, response.body

    # Second request to shared workspace
    workspace_get "/", workspace: workspace_shared
    assert_response :success
    # Action cable URL should now reference shared workspace
    assert_match %r{action-cable-url.*content="[^"]*\?wid=#{workspace_shared.external_id}"}, response.body
  end
end
