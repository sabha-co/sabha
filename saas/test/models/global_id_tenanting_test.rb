# frozen_string_literal: true

require_relative "../test_helper"

class GlobalIdTenantingTest < ActiveSupport::TestCase
  # Tests that GlobalID includes tenant context and enforces tenant isolation
  # The activerecord-tenanted gem extends GlobalID to include tenant parameter

  setup do
    @workspace_a = workspaces(:acme)
    @workspace_b = workspaces(:widgets)
    @tenant_a = @workspace_a.external_id.to_s
    @tenant_b = @workspace_b.external_id.to_s

    # Ensure tenant databases exist
    ApplicationRecord.create_tenant(@tenant_a) unless ApplicationRecord.tenant_exist?(@tenant_a)
    ApplicationRecord.create_tenant(@tenant_b) unless ApplicationRecord.tenant_exist?(@tenant_b)
  end

  test "GlobalIDs from different tenants are distinct" do
    gid_a = ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "same@example.com") do |u|
        u.name = "Same User A"
        u.role = :member
        u.verified_at = Time.current
      end
      user.to_global_id.to_s
    end

    gid_b = ApplicationRecord.with_tenant(@tenant_b) do
      user = User.find_or_create_by!(email_address: "same@example.com") do |u|
        u.name = "Same User B"
        u.role = :member
        u.verified_at = Time.current
      end
      user.to_global_id.to_s
    end

    # Same model, same ID could exist in both - but GIDs should be different
    assert_not_equal gid_a, gid_b, "GIDs should differ by tenant"
    assert_includes gid_a, "tenant=#{@tenant_a}"
    assert_includes gid_b, "tenant=#{@tenant_b}"
  end
end
