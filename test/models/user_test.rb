require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user does not prevent very long passwords" do
    users(:david).update(password: "secret" * 50)
    assert users(:david).valid?
  end

  test "password shorter than minimum length is invalid" do
    user = User.new(name: "Test", email_address: "short@example.com", password: "short")
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
  end

  test "password at exactly minimum length is valid" do
    user = User.new(name: "Test", email_address: "exact@example.com", password: "a" * User::MINIMUM_PASSWORD_LENGTH)
    assert user.valid?
  end

  test "blank password skips length validation" do
    user = User.new(name: "Test", email_address: "nopw@example.com")
    assert user.valid?
  end

  test "password_reset token is invalidated when the password is changed" do
    user = users(:david)
    token = user.generate_token_for(:password_reset)

    assert_equal user, User.find_by_token_for(:password_reset, token)

    user.update!(password: "newsecret12345")

    assert_nil User.find_by_token_for(:password_reset, token),
      "password_reset token must rotate when password_salt changes"
  end

  test "creating users grants membership to auto_join open rooms only" do
    auto_join_room = Rooms::Open.create!(name: "Auto Room", creator: users(:david), auto_join: true)
    non_auto_room = Rooms::Open.create!(name: "Manual Room", creator: users(:david))

    user = create_new_user

    assert user.member_of?(auto_join_room), "New user should be auto-joined to auto_join rooms"
    assert_not user.member_of?(non_auto_room), "New user should not be auto-joined to non-auto_join rooms"
  end

  test "a new user reaches existing threads in an auto_join room via derived access, without a thread membership" do
    auto_join_room = Rooms::Open.create!(name: "Auto Room", creator: users(:david), auto_join: true)
    parent_message = auto_join_room.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent_message, creator: users(:david))
    reply = thread.messages.create!(body: "existing reply", creator: users(:david))

    user = create_new_user

    assert_not Membership.exists?(room_id: thread.id, user_id: user.id),
      "signing up must not fan a membership row out into every existing thread"
    assert user.reachable_messages.exists?(id: reply.id),
      "the new member still reaches the thread's messages via parent-derived access"
    assert_not_includes Inbox::ThreadsQuery.new(user).call.map(&:id), parent_message.id,
      "a passive new member gets no inbox entry for a thread they never engaged with"
  end

  test "creating an unverified user does not post a welcome message" do
    original_room = Room.original

    assert_no_difference -> { Message.unscoped.where(room: original_room, welcome: true).count } do
      create_new_user
    end
  end

  test "verifying a user posts a welcome message in the original room" do
    original_room = Room.original
    user = create_new_user

    assert_difference -> { Message.unscoped.where(room: original_room, welcome: true).count } do
      user.verify_email!
    end
  end

  test "creating a bot posts a welcome message" do
    original_room = Room.original

    assert_difference -> { Message.unscoped.where(room: original_room, welcome: true).count }, 1 do
      User.create!(name: "Test Bot", bot_token: User.generate_bot_token, role: :bot)
    end

    assert_equal "has been added as a bot.", Message.unscoped.where(room: original_room, welcome: true).last.body.to_plain_text
  end

  test "deactivating a user deletes push subscriptions, searches, and deactivates all memberships including direct rooms" do
    user = users(:david)
    non_direct_count = user.memberships.without_direct_rooms.count
    # Direct room deactivation also deactivates the other user's membership in that room
    direct_room_ids = Membership.where(user_id: user.id).direct_rooms.where(active: true).pluck(:room_id)
    all_direct_memberships_count = Membership.where(room_id: direct_room_ids, active: true).count
    total_deactivated = non_direct_count + all_direct_memberships_count

    assert_no_difference -> { Membership.count } do  # Memberships are soft-deleted (active: false), not removed
    assert_difference -> { Membership.active.count }, -total_deactivated do  # All memberships deactivated
    assert_difference -> { Push::Subscription.count }, -user.push_subscriptions.count do
    assert_difference -> { Search.count }, -user.searches.count do
      user.deactivate
      assert user.reload.deactivated?
    end
    end
    end
    end
  end

  test "deactivating a user deactivates their direct rooms" do
    user = users(:david)
    other = users(:jason)
    direct_room = Rooms::Direct.find_or_create_for(User.where(id: [ user.id, other.id ]))
    assert direct_room.active?

    user.deactivate

    assert_not direct_room.reload.active?, "Direct room should be deactivated when a participant is deactivated"
  end

  test "reactivating a user restores their direct rooms" do
    user = users(:david)
    other = users(:jason)
    direct_room = Rooms::Direct.find_or_create_for(User.where(id: [ user.id, other.id ]))

    user.deactivate
    assert_not direct_room.reload.active?

    user.reactivate
    assert direct_room.reload.active?, "Direct room should be reactivated when participant is reactivated"
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

  # Email change tests

  test "update_email sets unconfirmed_email" do
    user = users(:david)
    assert user.update_email("newemail@example.com")

    assert_equal "newemail@example.com", user.unconfirmed_email
    assert_equal "david@37signals.com", user.email_address
  end

  test "update_email normalizes email to lowercase" do
    user = users(:david)
    user.update_email("NewEmail@Example.COM")

    assert_equal "newemail@example.com", user.unconfirmed_email
  end

  test "update_email returns true when email is same" do
    user = users(:david)
    assert user.update_email("david@37signals.com")

    assert_nil user.unconfirmed_email
  end

  test "update_email returns true when email is blank" do
    user = users(:david)
    assert user.update_email("")

    assert_nil user.unconfirmed_email
  end

  test "update_email returns false for invalid email format" do
    user = users(:david)
    assert_not user.update_email("not-an-email")

    assert_nil user.reload.unconfirmed_email
    assert_includes user.errors[:unconfirmed_email], "is invalid"
  end

  test "confirm_email_change! moves unconfirmed_email to email_address" do
    user = users(:david)
    user.update!(unconfirmed_email: "newemail@example.com")

    user.confirm_email_change!

    assert_equal "newemail@example.com", user.email_address
    assert_nil user.unconfirmed_email
  end

  test "confirm_email_change! does nothing when no pending change" do
    user = users(:david)
    original_email = user.email_address

    user.confirm_email_change!

    assert_equal original_email, user.email_address
  end

  test "cancel_email_change! clears unconfirmed_email" do
    user = users(:david)
    user.update!(unconfirmed_email: "newemail@example.com")

    user.cancel_email_change!

    assert_nil user.unconfirmed_email
  end

  test "pending_email_change? returns true when unconfirmed_email present" do
    user = users(:david)
    user.update!(unconfirmed_email: "newemail@example.com")

    assert user.pending_email_change?
  end

  test "pending_email_change? returns false when no unconfirmed_email" do
    user = users(:david)

    assert_not user.pending_email_change?
  end

  test "unconfirmed_email validation rejects invalid format" do
    user = users(:david)
    user.unconfirmed_email = "not-an-email"

    assert_not user.valid?
    assert_includes user.errors[:unconfirmed_email], "is invalid"
  end

  test "changing a bot's email does not enqueue an email_changed notification" do
    bot = users(:bender)
    bot.update_columns(email_address: "bot-old@example.com")

    UserMailer.expects(:email_changed).never

    bot.update!(email_address: "bot-new@example.com")
  end

  test "changing a human's email enqueues an email_changed notification to the old address" do
    user = users(:david)
    old_email = user.email_address

    mail = mock(deliver_later: true)
    UserMailer.expects(:email_changed).with(user, old_email).returns(mail)

    user.update!(email_address: "rotated@37signals.com")
  end

  test "transliterates name to ascii for search" do
    user = User.create!(name: "José García", email_address: "jose@example.com", password: "secret123456")
    assert_equal "Jose Garcia", user.ascii_name
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

    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:hq))
    end

    assert_equal 1, user.reload.current_streak
  end

  test "posting multiple messages on same day does not increment streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:hq))
    end
    assert_equal 1, user.reload.current_streak

    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:hq))
    end
    assert_equal 1, user.reload.current_streak

    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:pets))
    end
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
      perform_enqueued_jobs only: UpdateStreakJob do
        create_message(user: user, room: rooms(:hq))
      end
    end
    assert_equal 1, user.reload.current_streak

    # Post today - should increment
    travel_to Time.current do
      perform_enqueued_jobs only: UpdateStreakJob do
        create_message(user: user, room: rooms(:hq))
      end
    end

    assert_equal 2, user.reload.current_streak
  end

  test "streak resets to 1 when gap in posting" do
    user = users(:rachel)

    # Post 3 days ago
    travel_to 3.days.ago do
      perform_enqueued_jobs only: UpdateStreakJob do
        create_message(user: user, room: rooms(:hq))
      end
    end
    assert_equal 0, user.reload.current_streak, "streak should have decayed since last post was 3 days ago"

    # Post today (skipping yesterday) - should reset to 1
    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:hq))
    end

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

  test "posted_on? excludes welcome messages" do
    user = users(:rachel)
    rooms(:hq).post_welcome_message(user: user)

    assert_not user.posted_on?(Date.current)
  end

  test "welcome message does not prevent first real post from starting streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    rooms(:hq).post_welcome_message(user: user)
    assert_equal 0, user.reload.current_streak

    perform_enqueued_jobs only: UpdateStreakJob do
      create_message(user: user, room: rooms(:hq))
    end
    assert_equal 1, user.reload.current_streak
  end

  test "posted_on? excludes direct messages" do
    user = users(:rachel)
    dm = Rooms::Direct.create!(creator: user)
    create_message(user: user, room: dm)

    assert_not user.posted_on?(Date.current)
  end

  # Destroy cascade tests

  test "destroying a user cleans up all associated records without FK errors" do
    user = create_new_user

    # Create associated records across all association types
    room = rooms(:hq)
    message = Message.create!(room: room, creator: user, body: "Hello", client_message_id: SecureRandom.uuid)
    Boost.create!(message: messages(:first), booster: user, content: "🎉")
    Bookmark.create!(message: messages(:first), user: user)
    Search.create!(user: user, query: "test")
    user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")
    user.auth_tokens.create!(expires_at: 1.hour.from_now)
    user.block!(users(:jason))
    stub_dns_resolution("142.250.185.206")
    Push::Subscription.create!(user: user, endpoint: "https://fcm.googleapis.com/fcm/send/test", p256dh_key: "key", auth_key: "auth")

    assert_nothing_raised do
      user.destroy!
    end

    # Verify no orphaned records remain
    assert_not User.exists?(user.id)
    assert_empty Boost.where(booster_id: user.id)
    assert_empty Bookmark.where(user_id: user.id)
    assert_empty Search.where(user_id: user.id)
    assert_empty Session.where(user_id: user.id)
    assert_empty AuthToken.where(user_id: user.id)
    assert_empty Block.where(blocker_id: user.id)
    assert_empty Block.where(blocked_id: user.id)
    assert_empty Push::Subscription.where(user_id: user.id)
    assert_empty Message.unscoped.where(creator_id: user.id)
    assert_empty Membership.unscoped.where(user_id: user.id)
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

  # mentioning_messages tests

  test "mentioning_messages returns messages that mention the user" do
    room = rooms(:pets)
    david = users(:david)

    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "mentioning_msg_1"
    )

    assert_includes david.mentioning_messages, message
  end

  test "mentioning_messages returns @everyone messages" do
    room = rooms(:pets)
    david = users(:david)

    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: room,
      body: body_html,
      creator: users(:jason),
      client_message_id: "mentioning_everyone_1"
    )

    assert_includes david.mentioning_messages, message
  end

  test "mentioning_messages returns direct messages" do
    dm_room = rooms(:david_and_jason)
    david = users(:david)

    message = dm_room.messages.create!(
      body: "Hey david",
      creator: users(:jason),
      client_message_id: "mentioning_dm_1"
    )

    assert_includes david.mentioning_messages, message
  end

  test "mentioning_messages excludes messages not mentioning the user" do
    room = rooms(:pets)
    david = users(:david)

    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: david,
      client_message_id: "mentioning_exclude_1"
    )

    assert_not_includes david.mentioning_messages, message
  end

  test "mentioning_messages excludes inactive messages" do
    room = rooms(:pets)
    david = users(:david)

    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "mentioning_inactive_1"
    )

    message.deactivate!

    assert_not_includes david.mentioning_messages, message
  end

  test "mentioning_messages only returns messages from rooms user is a member of" do
    david = users(:david)
    room = rooms(:pets)

    # Create a message mentioning david in a room david is in
    msg_in_room = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "mentioning_in_room"
    )

    assert_includes david.mentioning_messages, msg_in_room
  end

  # User.matching

  test "matching returns empty array for blank query" do
    assert_equal [], User.matching("")
    assert_equal [], User.matching(nil)
    assert_equal [], User.matching("   ")
  end

  test "matching ranks exact first-name hits before partial matches" do
    User.create!(name: "Davidson", email_address: "davidson@example.com", verified_at: 1.day.ago)

    results = User.matching("David")
    david_pos = results.index { |u| u.id == users(:david).id }
    davidson_pos = results.index { |u| u.name == "Davidson" }

    assert david_pos.present? && davidson_pos.present?
    assert david_pos < davidson_pos
  end

  test "matching dedupes a user that matches both legs" do
    results = User.matching("David")
    assert_equal 1, results.count { |u| u.id == users(:david).id }
  end

  test "matching honors limit across both legs" do
    25.times { |i| User.create!(name: "Davidson #{i}", email_address: "d#{i}@example.com", verified_at: 1.day.ago) }

    assert_equal 5,  User.matching("Davidson", limit: 5).size
    assert_equal 20, User.matching("Davidson").size
  end

  test "matching caps even when exact-name hits exceed limit" do
    25.times { |i| User.create!(name: "David #{i}", email_address: "david#{i}@example.com", verified_at: 1.day.ago) }

    assert_equal 10, User.matching("David", limit: 10).size
  end

  # by_first_name / filtered_by dialect portability (SQLite + Postgres)

  test "by_first_name groups a multi-word name under its first token" do
    ada = User.create!(name: "Ada Lovelace", email_address: "ada@example.com", verified_at: 1.day.ago)

    assert_includes User.by_first_name("Ada"), ada
    assert_not_includes User.by_first_name("Lovelace"), ada
  end

  test "by_first_name matches a single-word name with no trailing split" do
    grace = User.create!(name: "Grace", email_address: "grace@example.com", verified_at: 1.day.ago)

    assert_includes User.by_first_name("Grace"), grace
  end

  test "filtered_by matches case-insensitively on every adapter" do
    # Postgres LIKE is case-sensitive; this fails there unless the scope renders
    # ILIKE. SQLite LIKE is case-insensitive, so it must keep matching too.
    alice = User.create!(name: "Alice", email_address: "alice@example.com", verified_at: 1.day.ago)

    assert_includes User.filtered_by("alice"), alice
    assert_includes User.filtered_by("ALICE"), alice
  end

  # User.sharing_rooms_with

  test "sharing_rooms_with returns members of rooms the bot shares" do
    bender = users(:bender)
    visible = User.sharing_rooms_with(bender)

    # bender is in watercooler with david, jason, nsa, rachel, kevin (and itself)
    assert_includes visible, users(:david)
    assert_includes visible, users(:rachel)
    assert_includes visible, bender
  end

  test "sharing_rooms_with excludes users from rooms the bot does not share" do
    bender = users(:bender)
    assert_not bender.rooms.include?(rooms(:designers))

    refute_includes User.sharing_rooms_with(bender), users(:jz)
  end

  test "sharing_rooms_with returns empty when the bot is in zero rooms" do
    bender = users(:bender)
    bender.memberships.destroy_all

    assert_equal [], User.sharing_rooms_with(bender).to_a
  end

  test "sharing_rooms_with dedupes users present in multiple shared rooms" do
    bender = users(:bender)
    Membership.create!(user: bender, room: rooms(:hq), involvement: :everything)
    # david is in both watercooler and hq with bender now

    results = User.sharing_rooms_with(bender).to_a
    assert_equal 1, results.count { |u| u.id == users(:david).id }
  end

  test "destroy_all_associated_records cleans up owned notification bundles + items (FK safe)" do
    user  = User.create!(name: "Bundle Owner", email_address: "bundle_owner@example.com")
    actor = users(:david)
    msg   = rooms(:designers).messages.create!(body: "<div>bundled</div>", creator: actor, client_message_id: "user_destroy_bundle_#{SecureRandom.hex(4)}")

    bundle = Notification::Bundle.create!(user: user, frequency: :hourly, starts_at: Time.current, ends_at: 1.hour.from_now)
    item   = Notification::BundleItem.create!(bundle: bundle, message: msg, actor: actor, kind: "mention")

    assert_nothing_raised { user.destroy }
    assert_nil Notification::Bundle.find_by(id: bundle.id)
    assert_nil Notification::BundleItem.find_by(id: item.id)
  end

  test "destroy_all_associated_records cleans up bundle items where this user was the actor" do
    actor   = User.create!(name: "Actor User", email_address: "bundle_actor@example.com")
    owner   = users(:jason)
    owner.notification_settings || owner.create_notification_settings!
    msg     = rooms(:designers).messages.create!(body: "<div>actor msg</div>", creator: actor, client_message_id: "user_destroy_actor_#{SecureRandom.hex(4)}")

    bundle = Notification::Bundle.create!(user: owner, frequency: :hourly, starts_at: Time.current, ends_at: 1.hour.from_now)
    item   = Notification::BundleItem.create!(bundle: bundle, message: msg, actor: actor, kind: "mention")

    assert_nothing_raised { actor.destroy }
    assert_nil Notification::BundleItem.find_by(id: item.id)
    assert Notification::Bundle.exists?(bundle.id), "the owner's bundle itself must remain — only the actor's row goes"
  end

  test "unseen_activity? true when a notification exists and the watermark is nil" do
    user = users(:david)
    user.update_column(:activity_seen_at, nil)
    rooms(:pets).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "unseen_mention_#{SecureRandom.hex(4)}"
    )

    assert user.reload.unseen_activity?
  end

  test "unseen_activity? false when watermark is newer than all notifications" do
    user = users(:david)
    rooms(:pets).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "seen_mention_#{SecureRandom.hex(4)}"
    )

    user.touch_activity_seen_at(Time.current + 1.second)
    assert_not user.reload.unseen_activity?
  end

  test "unseen_activity? true for boost-only recipients (the bug this fixes)" do
    user = users(:david)
    user.update_column(:activity_seen_at, 1.day.ago)
    message = rooms(:pets).messages.create!(body: "boost me", creator: user,
                                            client_message_id: "boost_only_unseen_#{SecureRandom.hex(4)}")

    perform_enqueued_jobs(only: Notification::DispatchJob) do
      message.boosts.create!(content: "🔥", booster: users(:jason))
    end

    assert user.reload.unseen_activity?,
      "boost notifications should light up the Activity dot"
  end

  test "touch_activity_seen_at is monotonic" do
    user = users(:david)
    later = Time.current
    earlier = later - 1.hour

    user.touch_activity_seen_at(later)
    user.touch_activity_seen_at(earlier)

    assert_in_delta later, user.reload.activity_seen_at, 1.second
  end

  test "advancing activity_seen_at broadcasts the sidebar indicator" do
    user = users(:david)
    user.update_column(:activity_seen_at, 1.day.ago)

    assert_turbo_stream_broadcasts [ user, :sidebar_activity_indicator ], count: 1 do
      user.touch_activity_seen_at(Time.current)
    end
  end

  test "touch_activity_seen_at does not broadcast when the watermark would not advance" do
    user = users(:david)
    user.touch_activity_seen_at(Time.current)

    assert_turbo_stream_broadcasts [ user, :sidebar_activity_indicator ], count: 0 do
      user.touch_activity_seen_at(1.hour.ago)
    end
  end

  test "mark_direct_messages_as_read clears unread on DM memberships up to the given time" do
    user = users(:david)
    dm = memberships(:david_david_and_kevin)
    # A minute old: loaded_at stamps truncate to seconds, so a message created
    # "now" would land after the stamp and legitimately stay unread.
    unseen = travel_to(1.minute.ago) { dm.room.messages.create!(creator: users(:kevin), body: "hi", client_message_id: "dm_mark_read") }
    rewind_unread_to dm, unseen

    user.mark_direct_messages_as_read(Time.current.iso8601)

    assert dm.reload.read?, "DM membership must be marked read"
  end

  test "mark_direct_messages_as_read leaves non-DM memberships untouched" do
    user = users(:david)
    non_dm = memberships(:david_designers)
    unseen = non_dm.room.messages.create!(creator: users(:jason), body: "hi", client_message_id: "non_dm_untouched")
    rewind_unread_to non_dm, unseen

    user.mark_direct_messages_as_read(Time.current.iso8601)

    assert non_dm.reload.unread?,
      "non-DM membership must not be touched by mark_direct_messages_as_read"
  end

  test "mark_inbox_as_read marks unread non-direct memberships read and advances activity_seen_at" do
    user = users(:david)
    user.update_column(:activity_seen_at, 1.day.ago)
    non_dm = memberships(:david_designers)
    unseen = travel_to(1.minute.ago) { non_dm.room.messages.create!(creator: users(:jason), body: "hi", client_message_id: "inbox_mark_read") }
    rewind_unread_to non_dm, unseen

    now_iso = Time.current.iso8601
    user.mark_inbox_as_read(
      messages_loaded_at: now_iso,
      notifications_loaded_at: now_iso,
      activity_loaded_at: now_iso
    )

    assert non_dm.reload.read?, "non-direct unread membership must be marked read"
    assert user.reload.activity_seen_at > 1.minute.ago,
      "activity_seen_at must advance to the activity_loaded_at"
  end

  test "mark_inbox_as_read falls back to Time.current when a loaded_at timestamp is stale (> 1 hour old)" do
    user = users(:david)
    membership = memberships(:david_designers)
    unseen = membership.room.messages.create!(creator: users(:jason), body: "hi", client_message_id: "inbox_stale_read")
    rewind_unread_to membership, unseen

    # A 2-hour-old stamp would leave the fresh message unread (it's newer than
    # the stamp). The freshness check rewrites it to Time.current, so the
    # membership ends up read.
    user.mark_inbox_as_read(
      messages_loaded_at: 2.hours.ago.iso8601,
      notifications_loaded_at: 2.hours.ago.iso8601,
      activity_loaded_at: 2.hours.ago.iso8601
    )

    assert membership.reload.read?,
      "stale loaded_at must be clamped to Time.current so unread is marked read"
  end

  test "mark_inbox_as_read falls back to Time.current when loaded_at is blank" do
    user = users(:david)
    membership = memberships(:david_designers)
    unseen = membership.room.messages.create!(creator: users(:jason), body: "hi", client_message_id: "inbox_blank_read")
    rewind_unread_to membership, unseen

    user.mark_inbox_as_read(
      messages_loaded_at: nil,
      notifications_loaded_at: nil,
      activity_loaded_at: nil
    )

    assert membership.reload.read?,
      "blank loaded_at must be clamped to Time.current so unread is marked read"
  end

  test "reachable_message resolves forum-post messages by forum access, not post membership" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    message = post.messages.first
    member = users(:kevin)   # auto-joined to the forum, no post membership
    outsider = users(:jason)
    forum.remove_member!(outsider, actor: users(:david)) # removed → no forum access

    assert_not Membership.exists?(room_id: post.id, user_id: member.id)
    assert_equal message, member.reachable_message(message.id), "a forum member reaches the post message"
    assert_raises(ActiveRecord::RecordNotFound) { outsider.reachable_message(message.id) }
  end
end
