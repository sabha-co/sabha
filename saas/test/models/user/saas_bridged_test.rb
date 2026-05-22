# frozen_string_literal: true

require_relative "../../test_helper"

class User::SaasBridgedTest < ActiveSupport::TestCase
  test "global_identity returns the workspace_membership's global identity in SaaS mode" do
    identity = GlobalIdentity.create!(name: "Bridge Reader", email_address: "bridge-reader@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Bridge Reader WS", creator: identity) do |workspace|
      tenant_id = workspace.external_id.to_s
      membership = WorkspaceMembership.find_by(tenant: tenant_id)

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.find(membership.user_id)
        assert_equal membership.global_identity, user.global_identity
      end
    end
  ensure
    identity&.destroy
  end

  test "sync_name_to_global_identity mirrors User#name onto the GlobalIdentity after update" do
    identity = GlobalIdentity.create!(name: "Original Name", email_address: "name-sync@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Name Sync WS", creator: identity) do |workspace|
      tenant_id = workspace.external_id.to_s
      membership = WorkspaceMembership.find_by(tenant: tenant_id)

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.find(membership.user_id)
        user.update!(name: "Renamed Person")
      end

      assert_equal "Renamed Person", identity.reload.name,
        "User#name change must mirror to GlobalIdentity#name"
    end
  ensure
    identity&.destroy
  end

  test "sync_name_to_global_identity rescues update failures so the User save still commits" do
    identity = GlobalIdentity.create!(name: "Rescue Origin", email_address: "name-rescue@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Name Rescue WS", creator: identity) do |workspace|
      tenant_id = workspace.external_id.to_s
      membership = WorkspaceMembership.find_by(tenant: tenant_id)

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.find(membership.user_id)
        GlobalIdentity.any_instance.expects(:update!).raises(StandardError, "boom")

        assert_nothing_raised do
          user.update!(name: "Renamed Despite Error")
        end

        assert_equal "Renamed Despite Error", user.reload.name,
          "the tenanted User save must not be rolled back when the GI mirror fails"
      end
    end
  ensure
    identity&.destroy
  end

  test "close_remote_connections scopes the disconnect by current_tenant in SaaS mode" do
    identity = GlobalIdentity.create!(name: "RC", email_address: "remote-conn@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Remote Conn WS", creator: identity) do |workspace|
      tenant_id = workspace.external_id.to_s
      membership = WorkspaceMembership.find_by(tenant: tenant_id)

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.find(membership.user_id)

        connections = mock("RemoteConnections")
        connections.expects(:disconnect).with(reconnect: false)
        ActionCable.server.remote_connections
          .expects(:where)
          .with(current_tenant: tenant_id, current_user: user)
          .returns(connections)

        user.send(:close_remote_connections)
      end
    end
  ensure
    identity&.destroy
  end
end
