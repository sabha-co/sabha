require "test_helper"

class Users::BansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create bans user and creates ban records from sessions" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    user.sessions.create!(ip_address: "203.0.113.2", user_agent: "Test")

    assert_difference -> { Ban.count }, 2 do
      post user_ban_url(user)
    end

    assert_redirected_to user_url(user)
    assert Ban.exists?(ip_address: "203.0.113.1", user: user)
    assert Ban.exists?(ip_address: "203.0.113.2", user: user)
  end

  test "create destroys user sessions" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")

    assert_difference -> { user.sessions.count }, -1 do
      post user_ban_url(user)
    end
  end

  test "create enqueues RemoveBannedContentJob" do
    user = users(:kevin)

    assert_enqueued_with(job: RemoveBannedContentJob, args: [ user ]) do
      post user_ban_url(user)
    end
  end

  test "RemoveBannedContentJob soft-deletes messages" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    message = Message.create!(room: rooms(:hq), creator: user, body: "Test message", client_message_id: "test-123")

    perform_enqueued_jobs do
      post user_ban_url(user)
    end

    # Messages are soft-deleted (deactivated), not destroyed
    assert_empty user.reload.messages  # scoped to active only
    assert Message.exists?(id: message.id)  # record still exists
    assert_not message.reload.active?  # but marked inactive
  end

  test "non-admins cannot ban users" do
    sign_in :kevin

    post user_ban_url(users(:jason))

    assert_response :forbidden
  end

  test "destroy removes ban records and sets user to active" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    user.ban

    assert user.reload.banned?
    assert_equal 1, user.bans.count

    assert_difference -> { Ban.count }, -1 do
      delete user_ban_url(user)
    end

    assert_redirected_to user_url(user)
    assert user.reload.active?
  end

  test "non-admins cannot unban users" do
    sign_in :kevin

    user = users(:jason)
    user.banned!

    delete user_ban_url(user)

    assert_response :forbidden
  end
end
