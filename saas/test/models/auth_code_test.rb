# frozen_string_literal: true

require_relative "../test_helper"

class AuthCodeTest < ActiveSupport::TestCase
  test "auto-generates code on create" do
    code = AuthCode.create!(global_identity: global_identities(:alice), purpose: :sign_in)
    assert code.code.present?
    assert_equal 6, code.code.length
  end

  test "auto-sets expires_at on create" do
    code = AuthCode.create!(global_identity: global_identities(:alice), purpose: :sign_in)
    assert code.expires_at.present?
    assert_in_delta 15.minutes.from_now, code.expires_at, 1.second
  end

  test "code must be unique" do
    existing = auth_codes(:alice_signin)
    # Try to create with same code (bypassing auto-generation)
    duplicate = AuthCode.new(
      global_identity: global_identities(:bob),
      code: existing.code,
      purpose: :sign_in,
      expires_at: 15.minutes.from_now
    )
    assert_not duplicate.valid?
  end

  test "expired? returns true for expired codes" do
    assert auth_codes(:expired_code).expired?
  end

  test "active scope excludes expired codes" do
    assert_includes AuthCode.active, auth_codes(:alice_signin)
    assert_not_includes AuthCode.active, auth_codes(:expired_code)
  end

  test "consume returns global_identity and destroys code" do
    code = auth_codes(:alice_signin)
    identity = code.global_identity

    result = code.consume

    assert_equal identity, result
    assert_raises(ActiveRecord::RecordNotFound) { code.reload }
  end

  test "find_active returns nil for expired codes" do
    code = auth_codes(:expired_code)
    assert_nil AuthCode.find_active(code.code)
  end

  test "find_active returns nil for unknown codes" do
    assert_nil AuthCode.find_active("UNKNOWN")
  end
end
