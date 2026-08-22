# frozen_string_literal: true

require_relative "../test_helper"

# Switching workspaces crosses a tenant boundary, so the selector links must
# force a full page load (data-turbo="false"). The app sidebar is a
# turbo-permanent frame; a Turbo Drive visit across workspaces would transplant
# the old tenant's sidebar (and keep its tenant-scoped cable subscriptions)
# instead of rebuilding for the new workspace.
class WorkspaceSwitchNavigationTest < ActionDispatch::IntegrationTest
  setup do
    [ workspaces(:acme), workspaces(:shared) ].each do |workspace|
      tenant_id = workspace.external_id.to_s
      ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
    end
  end

  test "workspace switch links force a full reload instead of a Turbo Drive visit" do
    sign_in_global_identity(global_identities(:alice))

    workspace_get "/", workspace: workspaces(:acme)

    assert_response :success
    assert_select "a.workspace-selector__item", minimum: 1
    assert_select "a.workspace-selector__item:not([data-turbo='false'])", false,
      "every workspace-switch link must force a full reload with data-turbo=\"false\""
  end
end
