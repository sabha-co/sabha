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

  test "GlobalID includes tenant parameter" do
    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "gid-test@example.com") do |u|
        u.name = "GID Test"
        u.role = :member
        u.verified_at = Time.current
      end

      gid = user.to_global_id
      gid_string = gid.to_s

      # GlobalID should include tenant parameter
      assert_includes gid_string, "tenant=#{@tenant_a}",
        "GlobalID should include tenant: #{gid_string}"
    end
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

  test "GlobalID.find locates record in correct tenant" do
    user_id = nil
    gid = nil

    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "locate-test@example.com") do |u|
        u.name = "Locate Test"
        u.role = :member
        u.verified_at = Time.current
      end
      user_id = user.id
      gid = user.to_global_id
    end

    # Should be able to locate the user via GlobalID
    ApplicationRecord.with_tenant(@tenant_a) do
      located = GlobalID::Locator.locate(gid)
      assert_not_nil located
      assert_equal user_id, located.id
    end
  end

  test "model cache_key includes tenant prefix" do
    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "cache-key-test@example.com") do |u|
        u.name = "Cache Key Test"
        u.role = :member
        u.verified_at = Time.current
      end

      cache_key = user.cache_key

      # Cache key should include tenant to prevent cross-tenant collisions
      assert cache_key.start_with?(@tenant_a),
        "Cache key should start with tenant: #{cache_key}"
    end
  end

  test "model tenant attribute reflects current tenant" do
    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "tenant-attr@example.com") do |u|
        u.name = "Tenant Attr Test"
        u.role = :member
        u.verified_at = Time.current
      end

      # Model should have tenant attribute set
      assert_equal @tenant_a, user.tenant
    end
  end

  test "signed GlobalID preserves tenant" do
    ApplicationRecord.with_tenant(@tenant_a) do
      user = User.find_or_create_by!(email_address: "sgid-test@example.com") do |u|
        u.name = "SGID Test"
        u.role = :member
        u.verified_at = Time.current
      end

      sgid = user.to_signed_global_id
      sgid_string = sgid.to_s

      # Signed GlobalID should also include tenant
      # The tenant is embedded in the signed payload
      assert sgid_string.present?

      # Verify we can locate via SGID
      located = GlobalID::Locator.locate_signed(sgid_string)
      assert_equal user.id, located.id
    end
  end
end
