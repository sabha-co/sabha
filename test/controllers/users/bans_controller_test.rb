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

  test "create deactivates non-DM memberships" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    room = Rooms::Open.create!(name: "Test Room", creator: users(:david))
    room.memberships.grant_to(user)

    assert user.memberships.without_direct_rooms.active.any?

    post user_ban_url(user)

    assert_empty user.memberships.without_direct_rooms.active
  end

  test "create deletes auth tokens" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    user.auth_tokens.create!(code: "123456", expires_at: 1.hour.from_now)

    assert user.auth_tokens.any?

    post user_ban_url(user)

    assert_empty user.reload.auth_tokens
  end

  test "create deletes push subscriptions" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    stub_dns_resolution("142.250.185.206")
    user.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/test", p256dh_key: "key", auth_key: "auth")

    assert user.push_subscriptions.any?

    post user_ban_url(user)

    assert_empty user.reload.push_subscriptions
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

    assert_redirected_to root_path
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

    assert_redirected_to root_path
  end

  test "create enqueues a ban notification email to the user" do
    user = users(:kevin)

    assert_enqueued_email_with(UserMailer, :banned, args: [ user ]) do
      post user_ban_url(user)
    end
  end

  test "destroy enqueues an unban notification email to the user" do
    user = users(:kevin)
    user.ban

    assert_enqueued_email_with(UserMailer, :unbanned, args: [ user ]) do
      delete user_ban_url(user)
    end
  end

  test "deactivate and reactivate do not enqueue ban or unban emails" do
    user = users(:kevin)

    assert_no_enqueued_emails do
      user.deactivate
      user.reactivate
    end
  end
end
