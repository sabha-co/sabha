# frozen_string_literal: true

require_relative "../../test_helper"

class SaasDesktopBadgeStateTest < ActiveSupport::TestCase
  include SaasTestHelper

  test "badge count stays inside the current tenant database" do
    with_provisioned_workspace(name: "Badge Tenant A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Badge Tenant B", creator: global_identities(:bob)) do |ws_b|
        tenant_a = ws_a.external_id.to_s
        tenant_b = ws_b.external_id.to_s

        membership_a = global_identities(:alice).workspace_memberships.find_by!(tenant: tenant_a)
        membership_b = global_identities(:bob).workspace_memberships.find_by!(tenant: tenant_b)
        user_a = membership_a.user
        user_b = membership_b.user

        ApplicationRecord.with_tenant(tenant_a) do
          room = user_a.memberships.first.room
          membership = user_a.memberships.find_by!(room: room)
          membership.update!(unread_notifications_count: 3, marked_unread: true, last_read_at: 1.day.ago, last_read_message_id: 0)
          assert_equal 1, Desktop::BadgeState.count_for(user_a)
        end

        ApplicationRecord.with_tenant(tenant_b) do
          assert_equal 0, Desktop::BadgeState.count_for(user_b)
        end
      end
    end
  end
end
