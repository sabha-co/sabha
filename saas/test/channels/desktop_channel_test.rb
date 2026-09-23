# frozen_string_literal: true

require_relative "../test_helper"

class SaasDesktopChannelTest < ActionCable::Channel::TestCase
  include SaasTestHelper

  tests DesktopChannel

  test "stream is scoped to the user's tenant through their GlobalID" do
    with_provisioned_workspace(name: "Desktop Stream WS", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      user = global_identities(:alice).workspace_memberships.find_by!(tenant: tenant_id).user

      ApplicationRecord.with_tenant(tenant_id) do
        assert_equal tenant_id, user.to_global_id.tenant
        assert_equal "desktop:#{user.to_gid_param}", DesktopChannel.broadcasting_for(user)
      end
    end
  end

  test "subscribed user in one workspace does not share another workspace stream" do
    with_provisioned_workspace(name: "Desktop Sub A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Desktop Sub B", creator: global_identities(:bob)) do |ws_b|
        tenant_a = ws_a.external_id.to_s
        tenant_b = ws_b.external_id.to_s

        user_a = global_identities(:alice).workspace_memberships.find_by!(tenant: tenant_a).user
        user_b = global_identities(:bob).workspace_memberships.find_by!(tenant: tenant_b).user

        stub_connection(current_user: user_a, current_tenant: tenant_a)
        ApplicationRecord.with_tenant(tenant_a) { subscribe }

        assert_has_stream ApplicationRecord.with_tenant(tenant_a) { DesktopChannel.broadcasting_for(user_a) }
        assert_has_no_stream ApplicationRecord.with_tenant(tenant_b) { DesktopChannel.broadcasting_for(user_b) }
      end
    end
  end

  test "badge count stays inside the current tenant database" do
    with_provisioned_workspace(name: "Badge Tenant A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Badge Tenant B", creator: global_identities(:bob)) do |ws_b|
        user_a = global_identities(:alice).workspace_memberships.find_by!(tenant: ws_a.external_id.to_s).user
        user_b = global_identities(:bob).workspace_memberships.find_by!(tenant: ws_b.external_id.to_s).user

        ApplicationRecord.with_tenant(ws_a.external_id.to_s) do
          user_a.memberships.first.update!(unread_notifications_count: 3, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)
          assert_equal 1, DesktopChannel.badge_for(user_a)[:count]
        end

        ApplicationRecord.with_tenant(ws_b.external_id.to_s) do
          assert_equal 0, DesktopChannel.badge_for(user_b)[:count]
        end
      end
    end
  end
end
