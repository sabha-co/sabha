# frozen_string_literal: true

require_relative "../test_helper"

class SaasDesktopChannelTest < ActionCable::Channel::TestCase
  include SaasTestHelper

  tests DesktopChannel

  test "stream name is scoped to current tenant in SaaS mode" do
    with_provisioned_workspace(name: "Desktop Stream WS", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s
      membership = global_identities(:alice).workspace_memberships.find_by!(tenant: tenant_id)
      user = membership.user

      ApplicationRecord.with_tenant(tenant_id) do
        assert_equal "desktop:#{tenant_id}:#{user.id}", DesktopChannel.stream_name_for(user)
      end
    end
  end

  test "subscribed user in one workspace does not share another workspace stream" do
    with_provisioned_workspace(name: "Desktop Sub A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Desktop Sub B", creator: global_identities(:bob)) do |ws_b|
        tenant_a = ws_a.external_id.to_s
        tenant_b = ws_b.external_id.to_s

        membership_a = global_identities(:alice).workspace_memberships.find_by!(tenant: tenant_a)
        user_a = membership_a.user

        stub_connection(current_user: user_a, current_tenant: tenant_a)
        ApplicationRecord.with_tenant(tenant_a) { subscribe }

        expected_stream = "desktop:#{tenant_a}:#{user_a.id}"
        foreign_stream  = "desktop:#{tenant_b}:#{user_a.id}"

        assert_has_stream expected_stream
        assert_has_no_stream foreign_stream
      end
    end
  end
end
