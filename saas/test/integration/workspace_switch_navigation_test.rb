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

  test "Room info preferences are scoped to the workspace as well as the local user" do
    sign_in_global_identity(global_identities(:alice))

    keys = []
    local_ids = []
    [ "Room info A", "Room info B" ].each do |name|
      with_provisioned_workspace(name: name, creator: global_identities(:alice)) do |workspace|
        room_id = ApplicationRecord.with_tenant(workspace.external_id.to_s) do
          local_ids << [ Account.sole.id, User.find_by!(email_address: global_identities(:alice).email_address).id ]
          Room.first.id
        end
        workspace_get "/rooms/#{room_id}", workspace: workspace

        assert_response :success
        keys << css_select("[data-thread-panel-storage-key-value]").sole["data-thread-panel-storage-key-value"]
      end
    end

    assert_equal local_ids.first, local_ids.last, "the workspaces must exercise colliding local IDs"
    assert_not_equal keys.first, keys.last
  end
end
