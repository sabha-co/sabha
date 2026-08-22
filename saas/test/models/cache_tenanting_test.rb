# frozen_string_literal: true

require_relative "../test_helper"

class CacheTenantingTest < ActiveSupport::TestCase
  # Tests that cache keys are properly scoped with tenant prefix in SaaS mode
  # Prevents cache collisions between workspaces

  setup do
    @workspace_a = workspaces(:acme)
    @workspace_b = workspaces(:widgets)
    @tenant_a = @workspace_a.external_id.to_s
    @tenant_b = @workspace_b.external_id.to_s

    # Ensure tenant databases exist
    ApplicationRecord.create_tenant(@tenant_a) unless ApplicationRecord.tenant_exist?(@tenant_a)
    ApplicationRecord.create_tenant(@tenant_b) unless ApplicationRecord.tenant_exist?(@tenant_b)
  end

  test "tenant_cache_key includes tenant prefix in SaaS mode" do
    ApplicationRecord.with_tenant(@tenant_a) do
      key = ApplicationRecord.tenant_cache_key("users/online_count")
      assert_equal "#{@tenant_a}/users/online_count", key
    end

    ApplicationRecord.with_tenant(@tenant_b) do
      key = ApplicationRecord.tenant_cache_key("users/online_count")
      assert_equal "#{@tenant_b}/users/online_count", key
    end
  end

  test "room active_member_count_cache_key includes tenant" do
    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "test@example.com") do |u|
        u.name = "Test"
        u.role = :administrator
        u.verified_at = Time.current
      end

      room = Rooms::Open.find_or_create_by!(name: "Test Room") do |r|
        r.slug = "test-room"
        r.creator = user
      end

      cache_key = room.send(:active_member_count_cache_key)

      # Key should include tenant prefix
      assert cache_key.start_with?("#{@tenant_a}:"), "Cache key should start with tenant: #{cache_key}"
      assert_includes cache_key, "room"
      assert_includes cache_key, room.id.to_s
    end
  end

  test "tenant_cache_key returns raw key without tenant context" do
    # Without tenant context, key should still work (for self-hosted mode)
    ApplicationRecord.without_tenant do
      key = ApplicationRecord.tenant_cache_key("users/online_count")
      assert_equal "users/online_count", key
    end
  end
end
