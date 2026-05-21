# frozen_string_literal: true

require_relative "../test_helper"

class GlobalSessionTest < ActiveSupport::TestCase
  test "session expires after 30 days by default" do
    session = global_identities(:alice).global_sessions.create!(
      user_agent: "Test",
      ip_address: "127.0.0.1"
    )

    assert_not session.expired?
    assert_in_delta 30.days.from_now, session.expires_at, 1.second
  end

  test "expired? returns true for past expires_at" do
    assert global_sessions(:expired_session).expired?
  end

  test "expired? returns false for future expires_at" do
    assert_not global_sessions(:alice_session).expired?
  end

  test "expired? returns false when expires_at is nil" do
    session = global_sessions(:alice_session)
    session.update_column(:expires_at, nil)
    assert_not session.expired?
  end

  test "active scope excludes expired sessions" do
    assert_includes GlobalSession.active, global_sessions(:alice_session)
    assert_not_includes GlobalSession.active, global_sessions(:expired_session)
  end

  test "active scope includes sessions with nil expires_at" do
    session = global_sessions(:alice_session)
    session.update_column(:expires_at, nil)
    assert_includes GlobalSession.active, session
  end

  test "resume updates session metadata" do
    session = global_sessions(:alice_session)

    session.resume(user_agent: "New Agent", ip_address: "5.6.7.8")
    session.reload

    assert_equal "New Agent", session.user_agent
    assert_equal "5.6.7.8", session.ip_address
  end

  test "has_secure_token generates token" do
    session = global_identities(:bob).global_sessions.create!(
      user_agent: "Test",
      ip_address: "127.0.0.1"
    )
    assert session.token.present?
    assert session.token.length >= 20
  end
end
