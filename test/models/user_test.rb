require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user does not prevent very long passwords" do
    users(:david).update(password: "secret" * 50)
    assert users(:david).valid?
  end

  test "creating users grants membership to the open rooms" do
    assert_difference -> { Membership.count }, +Rooms::Open.count do
      create_new_user
    end
  end

  test "deactivating a user deletes push subscriptions, searches, and deactivates memberships for non-direct rooms" do
    user = users(:david)
    membership_count_before = user.memberships.without_direct_rooms.count

    assert_no_difference -> { Membership.count } do  # Memberships are soft-deleted (active: false), not removed
    assert_difference -> { Membership.active.count }, -membership_count_before do  # But active count decreases
    assert_difference -> { Push::Subscription.count }, -user.push_subscriptions.count do
    assert_difference -> { Search.count }, -user.searches.count do
      user.deactivate
      assert user.reload.deactivated?
    end
    end
    end
    end
  end

  test "deactivating a user deletes their sessions" do
    assert_changes -> { users(:david).sessions.count }, from: 1, to: 0 do
      users(:david).deactivate
    end
  end

  test "deactivating a user deletes their auth tokens" do
    user = users(:david)
    user.auth_tokens.create!(expires_at: 1.hour.from_now)

    assert_changes -> { user.auth_tokens.count }, from: 1, to: 0 do
      user.deactivate
    end
  end

  test "reactivating a user restores their memberships" do
    user = users(:david)
    initial_count = Membership.where(user_id: user.id, active: true).without_direct_rooms.count

    assert initial_count > 0, "Precondition: user should have memberships"

    user.deactivate
    user.reload

    assert_equal 0, Membership.where(user_id: user.id, active: true).without_direct_rooms.count
    inactive_count = Membership.where(user_id: user.id, active: false).without_direct_rooms.count
    assert inactive_count > 0, "Memberships should be deactivated"

    user.reactivate
    user.reload

    restored_count = Membership.where(user_id: user.id, active: true).without_direct_rooms.count
    assert_equal initial_count, restored_count, "Memberships should be restored after reactivation"
  end

  test "email validation rejects invalid format" do
    user = User.new(name: "Test", email_address: "not-an-email", password: "secret123456")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "is invalid"
  end

  test "email validation accepts valid format" do
    user = User.new(name: "Test", email_address: "valid@example.com", password: "secret123456")
    assert user.valid?
  end

  test "email validation accepts emails with plus signs" do
    user = User.new(name: "Test", email_address: "valid+tag@example.com", password: "secret123456")
    assert user.valid?
  end

  test "transliterates name to ascii for search" do
    user = User.create!(name: "José García", email_address: "jose@example.com", password: "secret123456")
    assert_equal "Jose Garcia", user.ascii_name
  end

  test "destroying a user removes their email subscriptions" do
    user = create_new_user

    assert_difference -> { Mailkick::Subscription.count }, -1 do
      user.destroy
    end
  end

  # Blocking tests

  test "block! creates a block record" do
    assert_difference -> { Block.count }, 1 do
      users(:david).block!(users(:jason))
    end

    assert users(:david).blocked?(users(:jason))
  end

  test "block! is idempotent" do
    users(:david).block!(users(:jason))

    assert_no_difference -> { Block.count } do
      users(:david).block!(users(:jason))
    end
  end

  test "unblock! removes the block record" do
    users(:david).block!(users(:jason))

    assert_difference -> { Block.count }, -1 do
      users(:david).unblock!(users(:jason))
    end

    assert_not users(:david).blocked?(users(:jason))
  end

  test "blocked? returns true when user is blocked" do
    users(:david).block!(users(:jason))

    assert users(:david).blocked?(users(:jason))
    assert_not users(:jason).blocked?(users(:david))
  end

  test "blocked_by? returns true when blocked by other user" do
    users(:david).block!(users(:jason))

    assert users(:jason).blocked_by?(users(:david))
    assert_not users(:david).blocked_by?(users(:jason))
  end

  test "can_ping? returns false when either user blocked the other" do
    assert users(:david).can_ping?(users(:jason))
    assert users(:jason).can_ping?(users(:david))

    users(:david).block!(users(:jason))

    assert_not users(:david).can_ping?(users(:jason))
    assert_not users(:jason).can_ping?(users(:david))
  end

  test "blocked_in? returns true in one-on-one room when blocked" do
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ])
    users(:david).block!(users(:jason))

    assert users(:david).blocked_in?(room)
    assert users(:jason).blocked_in?(room)
  end

  test "blocked_in? returns false for non-direct rooms" do
    users(:david).block!(users(:jason))

    assert_not users(:david).blocked_in?(rooms(:hq))
  end

  # Role tests

  test "can_moderate? returns true for moderators and administrators" do
    users(:kevin).update!(role: :member)
    assert_not users(:kevin).can_moderate?

    users(:kevin).update!(role: :moderator)
    assert users(:kevin).can_moderate?

    users(:kevin).update!(role: :administrator)
    assert users(:kevin).can_moderate?
  end

  test "can_delete_message? allows moderators to delete any message" do
    moderator = users(:kevin)
    moderator.update!(role: :moderator)
    message = messages(:first)

    assert moderator.can_delete_message?(message)
  end

  test "can_delete_message? allows creator to delete own message" do
    message = messages(:first)
    creator = message.creator

    assert creator.can_delete_message?(message)
  end

  test "can_delete_message? denies members deleting others messages" do
    member = users(:kevin)
    member.update!(role: :member)
    message = messages(:first)

    assert_not member.can_delete_message?(message)
  end

  # Streak tests

  test "current_streak starts at zero for new users" do
    user = create_new_user
    assert_equal 0, user.current_streak
  end

  test "posting a message in open room sets streak to 1" do
    user = users(:rachel) # rachel has no fixture messages
    user.update_column(:current_streak, 0)

    create_message(user: user, room: rooms(:hq))

    assert_equal 1, user.reload.current_streak
  end

  test "posting multiple messages on same day does not increment streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    create_message(user: user, room: rooms(:hq))
    assert_equal 1, user.reload.current_streak

    create_message(user: user, room: rooms(:hq))
    assert_equal 1, user.reload.current_streak

    create_message(user: user, room: rooms(:pets))
    assert_equal 1, user.reload.current_streak
  end

  test "posting in direct room does not affect streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    dm = Rooms::Direct.create!(creator: user)
    create_message(user: user, room: dm)

    assert_equal 0, user.reload.current_streak
  end

  test "posting in thread of direct room does not affect streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    dm = Rooms::Direct.create!(creator: user)
    dm_message = create_message(user: user, room: dm)
    thread = Rooms::Thread.create!(parent_message: dm_message, creator: user)

    create_message(user: user, room: thread)

    assert_equal 0, user.reload.current_streak
  end

  test "streak increments when posting on consecutive days" do
    user = users(:rachel)

    # Post yesterday
    travel_to 1.day.ago do
      create_message(user: user, room: rooms(:hq))
    end
    assert_equal 1, user.reload.current_streak

    # Post today - should increment
    travel_to Time.current do
      create_message(user: user, room: rooms(:hq))
    end

    assert_equal 2, user.reload.current_streak
  end

  test "streak resets to 1 when gap in posting" do
    user = users(:rachel)

    # Post 3 days ago
    travel_to 3.days.ago do
      create_message(user: user, room: rooms(:hq))
    end
    assert_equal 1, user.reload.current_streak

    # Post today (skipping yesterday) - should reset to 1
    create_message(user: user, room: rooms(:hq))

    assert_equal 1, user.reload.current_streak
  end

  test "posted_on? returns true when user posted on date" do
    user = users(:rachel)
    create_message(user: user, room: rooms(:hq))

    assert user.posted_on?(Date.current)
  end

  test "posted_on? returns false when user did not post on date" do
    user = users(:rachel)

    assert_not user.posted_on?(Date.current)
  end

  test "posted_on? excludes direct messages" do
    user = users(:rachel)
    dm = Rooms::Direct.create!(creator: user)
    create_message(user: user, room: dm)

    assert_not user.posted_on?(Date.current)
  end

  private
    def create_new_user
      User.create!(name: "User", email_address: "user@example.com", password: "secret123456")
    end

    def create_message(user:, room:, body: "Test message")
      Message.create!(
        room: room,
        creator: user,
        body: body,
        client_message_id: SecureRandom.uuid
      )
    end
end
