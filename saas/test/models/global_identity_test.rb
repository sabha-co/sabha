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

  test "workspaces returns associated workspaces" do
    identity = global_identities(:alice)
    assert_includes identity.workspaces.pluck(:external_id), 1000001
  end

  test "destroying identity cascades to sessions and auth_codes" do
    identity = GlobalIdentity.create!(name: "Cascade", email_address: "cascade@example.com")
    identity.global_sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
    identity.auth_codes.create!(code: "TEST12", expires_at: 15.minutes.from_now, purpose: :sign_in)

    assert_difference [ "GlobalSession.count", "AuthCode.count" ], -1 do
      identity.destroy
    end
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
    with_provisioned_workspace(name: "Sync Skip Test", creator: global_identities(:alice)) do |workspace|
      membership = global_identities(:alice).workspace_memberships.find_by(tenant: workspace.external_id.to_s)
      original_user_id = membership.user_id
      membership.update_column(:user_id, nil)

      assert_nothing_raised do
        global_identities(:alice).sync_email_to_workspaces("skipped@example.com")
      end

      # Restore for other tests using this membership
      membership.update_column(:user_id, original_user_id)
    end
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
end
