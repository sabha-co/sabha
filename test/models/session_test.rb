require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
  end

  test "creating a session updates user last_authenticated_at" do
    @user.update_column(:last_authenticated_at, 1.week.ago)

    travel_to Time.current do
      @user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
      assert_in_delta Time.current, @user.reload.last_authenticated_at, 2.seconds
    end
  end

  test "session expires after 30 days" do
    session = @user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")

    assert_not session.expired?
    assert session.expires_at.present?
    assert_in_delta 30.days.from_now, session.expires_at, 1.second
  end

  test "expired session returns true for expired?" do
    session = @user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
    session.update_column(:expires_at, 1.day.ago)

    assert session.expired?
  end

  test "active scope excludes expired sessions" do
    active_session = @user.sessions.create!(user_agent: "Active", ip_address: "127.0.0.1")
    expired_session = @user.sessions.create!(user_agent: "Expired", ip_address: "127.0.0.1")
    expired_session.update_column(:expires_at, 1.day.ago)

    assert_includes @user.sessions.active, active_session
    assert_not_includes @user.sessions.active, expired_session
  end

  test "active scope includes sessions with nil expires_at" do
    session = @user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
    session.update_column(:expires_at, nil)

    assert_includes @user.sessions.active, session
  end
end
