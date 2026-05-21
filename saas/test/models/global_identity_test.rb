# frozen_string_literal: true

require_relative "../test_helper"

class GlobalIdentityTest < ActiveSupport::TestCase
  test "requires email_address" do
    identity = GlobalIdentity.new
    assert_not identity.valid?
    assert_includes identity.errors[:email_address], "can't be blank"
  end

  test "requires valid email format" do
    identity = GlobalIdentity.new(email_address: "invalid")
    assert_not identity.valid?
    assert_includes identity.errors[:email_address], "is invalid"
  end

  test "rejects disposable email addresses with actionable message" do
    identity = GlobalIdentity.new(email_address: "test@mailinator.com")
    assert_not identity.valid?
    assert_includes identity.errors[:email_address], "looks like a temporary email address. We discourage use of disposable emails — please use a permanent one instead."
  end

  test "normalizes email to lowercase" do
    identity = GlobalIdentity.new(email_address: "  TEST@Example.COM  ")
    assert_equal "test@example.com", identity.email_address
  end

  test "email must be unique" do
    GlobalIdentity.create!(name: "Test", email_address: "unique@example.com")
    duplicate = GlobalIdentity.new(name: "Test", email_address: "UNIQUE@example.com")
    assert_not duplicate.valid?
  end

  test "verified? reflects verified_at" do
    assert global_identities(:alice).verified?
    assert_not global_identities(:unverified).verified?
  end

  test "verify! sets verified_at" do
    identity = global_identities(:unverified)
    identity.verify!
    assert identity.verified?
  end

  test "destroying identity cascades to sessions and auth_codes" do
    identity = GlobalIdentity.create!(name: "Cascade", email_address: "cascade@example.com")
    identity.global_sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
    identity.auth_codes.create!(code: "TEST12", expires_at: 15.minutes.from_now, purpose: :sign_in)

    assert_difference [ "GlobalSession.count", "AuthCode.count" ], -1 do
      identity.destroy
    end
  end

  # Superadmin domain restriction tests

  test "superadmin? is true when superadmin flag set and email domain is allowed" do
    identity = GlobalIdentity.new(email_address: "admin@sabha.co", superadmin: true)
    assert identity.superadmin?
  end

  test "superadmin? is true for superforum.io domain" do
    identity = GlobalIdentity.new(email_address: "admin@superforum.io", superadmin: true)
    assert identity.superadmin?
  end

  test "superadmin? is false when superadmin flag set but email domain is not allowed" do
    identity = GlobalIdentity.new(email_address: "hacker@evil.com", superadmin: true)
    assert_not identity.superadmin?
  end

  test "superadmin? is false when email domain is allowed but flag is not set" do
    identity = GlobalIdentity.new(email_address: "user@sabha.co", superadmin: false)
    assert_not identity.superadmin?
  end

  # Email change tests

  test "unconfirmed_email normalizes to lowercase" do
    alice = global_identities(:alice)
    alice.unconfirmed_email = "  NEW@Example.COM  "
    assert_equal "new@example.com", alice.unconfirmed_email
  end

  test "confirm_email_change! propagates to tenant User records" do
    # Use a throwaway identity to avoid mutating shared fixtures
    identity = GlobalIdentity.create!(name: "Email Change", email_address: "emailchange@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Email Sync Test", creator: identity) do |workspace|
      membership = identity.workspace_memberships.find_by(tenant: workspace.external_id.to_s)

      identity.update!(unconfirmed_email: "newaddress@example.com")
      result = identity.confirm_email_change!

      assert_equal [ "emailchange@example.com", "newaddress@example.com" ], result

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        user = User.find(membership.user_id)
        assert_equal "newaddress@example.com", user.email_address
      end
    end
  ensure
    identity&.destroy
  end

  test "sync_email_to_workspaces skips memberships without user_id" do
    # Use a throwaway identity to avoid mutating shared fixture tenant Users
    identity = GlobalIdentity.create!(name: "Sync Skip", email_address: "syncskip@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Sync Skip Test", creator: identity) do |workspace|
      membership = identity.workspace_memberships.find_by(tenant: workspace.external_id.to_s)
      membership.update_column(:user_id, nil)

      assert_nothing_raised do
        identity.sync_email_to_workspaces("skipped@example.com")
      end
    end
  ensure
    identity&.destroy
  end

  # Workspace limit tests

  test "workspace_limit_reached? is false when under limit" do
    identity = global_identities(:alice)
    assert_not identity.workspace_limit_reached?
  end

  test "workspace_limit_reached? is true when at limit" do
    identity = global_identities(:alice)
    # Alice owns 1 workspace (acme), so limit of 1 should be reached
    original = GlobalIdentity::MAX_WORKSPACES
    GlobalIdentity.send(:remove_const, :MAX_WORKSPACES)
    GlobalIdentity.const_set(:MAX_WORKSPACES, 1)
    assert identity.workspace_limit_reached?
  ensure
    GlobalIdentity.send(:remove_const, :MAX_WORKSPACES)
    GlobalIdentity.const_set(:MAX_WORKSPACES, original)
  end

  test "email_available? checks primary email_address only" do
    alice = global_identities(:alice)

    # Alice's primary email is taken
    assert_not GlobalIdentity.email_available?(alice.email_address)
    # New email is available
    assert GlobalIdentity.email_available?("brandnew@example.com")
    # Excluding self works
    assert GlobalIdentity.email_available?(alice.email_address, excluding_id: alice.id)
  end

  test "rejects signup when terms checkbox is unchecked" do
    identity = GlobalIdentity.new(name: "Alice", email_address: "newalice@example.com", terms_of_service: "0")
    assert_not identity.valid?(:create)
    assert_includes identity.errors[:terms_of_service], "must be accepted"
  end

  test "stamps accepted_terms_at when terms checkbox is checked" do
    identity = GlobalIdentity.create!(name: "Alice", email_address: "newalice@example.com", terms_of_service: "1")
    assert_not_nil identity.accepted_terms_at
  end

  test "accepted_terms_at is preserved across subsequent updates" do
    identity = GlobalIdentity.create!(name: "Alice", email_address: "newalice@example.com", terms_of_service: "1")
    original_acceptance = identity.accepted_terms_at
    travel 1.day do
      identity.update!(name: "Renamed Alice")
    end
    assert_equal original_acceptance, identity.reload.accepted_terms_at
  end
end
