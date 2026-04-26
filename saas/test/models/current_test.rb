# frozen_string_literal: true

require_relative "../test_helper"

class SaasCurrentTest < ActiveSupport::TestCase
  setup do
    @workspace_a = workspaces(:acme)
    @workspace_b = workspaces(:widgets)
    @tenant_a = @workspace_a.external_id.to_s
    @tenant_b = @workspace_b.external_id.to_s

    [ @tenant_a, @tenant_b ].each do |tenant|
      ApplicationRecord.create_tenant(tenant) unless ApplicationRecord.tenant_exist?(tenant)
      ApplicationRecord.with_tenant(tenant) do
        Account.find_or_create_by!(singleton_guard: 0) { |a| a.name = "Account-#{tenant}" }
      end
    end

    Current.reset
  end

  test "workspace_membership= cascades into Current.user" do
    membership = workspace_memberships(:alice_acme)
    membership.create_user!

    Current.workspace_membership = membership

    assert_equal membership.user, Current.user
  end

  test "workspace_membership= nil clears Current.user" do
    membership = workspace_memberships(:alice_acme)
    membership.create_user!
    Current.workspace_membership = membership
    Current.workspace_membership = nil

    assert_nil Current.user
  end

  test "Current.workspace recomputes after reset when tenant changes" do
    workspace_a = ApplicationRecord.with_tenant(@tenant_a) { Current.workspace }
    assert_equal @workspace_a, workspace_a

    # Without reset, the memoized value would persist across tenants
    leaked = ApplicationRecord.with_tenant(@tenant_b) { Current.workspace }
    assert_equal @workspace_a, leaked, "guard: memoization should leak without reset"

    Current.reset

    fresh = ApplicationRecord.with_tenant(@tenant_b) { Current.workspace }
    assert_equal @workspace_b, fresh
  end

  test "Current.account recomputes after reset when tenant changes" do
    account_a = ApplicationRecord.with_tenant(@tenant_a) { Current.account }
    assert_equal @tenant_a, account_a.tenant

    # Without reset, the memoized account from tenant A leaks across tenant boundaries
    leaked = ApplicationRecord.with_tenant(@tenant_b) { Current.account }
    assert_equal @tenant_a, leaked.tenant, "guard: memoization should leak without reset"

    Current.reset

    fresh = ApplicationRecord.with_tenant(@tenant_b) { Current.account }
    assert_equal @tenant_b, fresh.tenant
  end
end
