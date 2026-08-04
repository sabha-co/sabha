require "test_helper"
require "rails/dom/testing/assertions"

class RoomTest < ActiveSupport::TestCase
  include ActionCable::TestHelper, Rails::Dom::Testing::Assertions::SelectorAssertions

  test "matching finds a room case-insensitively on every adapter" do
    # ILIKE on Postgres, LIKE on SQLite — a bare LIKE would miss this on Postgres.
    room = Rooms::Open.create!(name: "General", creator: users(:david))

    assert_includes Room.matching("general"), room
    assert_includes Room.matching("GENERAL"), room
  end

  test "last_active_at is set on room creation" do
    room = Rooms::Open.create!(name: "New Room", creator: users(:david))
    assert room.last_active_at.present?
    assert_in_delta Time.current, room.last_active_at, 2.seconds
  end

  test "grant membership to user" do
    rooms(:watercooler).memberships.grant_to(users(:kevin))
    assert rooms(:watercooler).users.include?(users(:kevin))
  end

  test "involve_user with unread marks a read membership unread at the last message" do
    room = rooms(:watercooler)
    last_message = room.messages.create!(creator: users(:jason), body: "Latest", client_message_id: "involve_unread")
    membership = room.memberships.find_by!(user: users(:david))
    catch_up membership

    room.involve_user(users(:david), unread: true)

    membership.reload
    assert membership.unread?
    assert_equal last_message, membership.first_unread_message
  end

  test "involve_user with unread does not move an already-unread anchor" do
    room = rooms(:watercooler)
    first = room.messages.create!(creator: users(:jason), body: "First", client_message_id: "involve_anchor_1")
    room.messages.create!(creator: users(:jason), body: "Second", client_message_id: "involve_anchor_2")
    membership = room.memberships.find_by!(user: users(:david))
    rewind_unread_to membership, first

    room.involve_user(users(:david), unread: true)

    assert_equal first, membership.reload.first_unread_message
  end

  test "revoke membership from user" do
    rooms(:watercooler).memberships.revoke_from(users(:david))
    assert_not rooms(:watercooler).users.include?(users(:david))
  end

  test "revoke_from raises LastVisibleMemberError when removing last visible member from closed room" do
    room = rooms(:designers)
    visible = room.memberships.visible.to_a
    visible[1..].each { |m| m.update!(involvement: :invisible) }

    assert_raises(Membership::LastVisibleMemberError) do
      room.memberships.revoke_from(visible.first.user)
    end

    assert visible.first.reload.active?, "membership should not have been revoked"
  end

  test "revoke_from allows removing members from open rooms freely" do
    room = rooms(:hq)
    user = room.memberships.visible.first.user

    assert_nothing_raised do
      room.memberships.revoke_from(user)
    end
  end

  test "revise memberships" do
    rooms(:watercooler).memberships.revise(granted: users(:kevin), revoked: users(:david))
    assert rooms(:watercooler).users.include?(users(:kevin))
    assert_not rooms(:watercooler).users.include?(users(:david))
  end

  test "create for users by giving them immediate membership" do
    room = Rooms::Closed.create_for({ name: "Hello!", creator: users(:david) }, users: [ users(:kevin), users(:david) ])
    assert room.users.include?(users(:kevin))
    assert room.users.include?(users(:david))
  end

  test "default involvement for new users" do
    room = Rooms::Closed.create_for({ name: "Hello!", creator: users(:david) }, users: [ users(:kevin), users(:david) ])
    assert room.memberships.all? { |m| m.involved_in_mentions? }
  end

  test "destroying a room removes thread rooms created from its messages" do
    room = Rooms::Open.create!(name: "Test Room", creator: users(:david))
    room.memberships.grant_to(users(:david))

    # Create a message in the room
    message = room.messages.create!(body: "Parent message", creator: users(:david))

    # Create a thread from that message
    thread = Rooms::Thread.create!(parent_message: message, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread.messages.create!(body: "Thread reply", creator: users(:david))

    thread_id = thread.id
    message_id = message.id

    # Destroy the room
    room.destroy

    # Thread room should be destroyed
    assert_not Rooms::Thread.exists?(thread_id), "Thread room should be destroyed when parent room is destroyed"
    # Parent message should be destroyed
    assert_not Message.exists?(message_id), "Message should be destroyed when room is destroyed"
  end

  test "destroying a room removes inactive memberships and messages" do
    room = Rooms::Open.create!(name: "Test Room", creator: users(:david))
    room.memberships.grant_to(users(:david))

    # Create a message and then deactivate it
    message = room.messages.create!(body: "Test message", creator: users(:david))
    message.deactivate!

    # Deactivate the membership
    membership = Membership.find_by(room: room, user: users(:david))
    membership.deactivate!

    message_id = message.id
    membership_id = membership.id

    # Destroy the room
    room.destroy

    # Inactive records should also be destroyed
    assert_not Message.exists?(message_id), "Inactive message should be destroyed"
    assert_not Membership.exists?(membership_id), "Inactive membership should be destroyed"
  end

  test "original? identifies the first-created room" do
    assert rooms(:hq).original?
    assert_not rooms(:pets).original?
  end

  test "cannot deactivate the original room" do
    assert_raises(Room::CannotDeleteOriginalError) { rooms(:hq).deactivate }
  end

  test "can deactivate a non-original room" do
    rooms(:pets).deactivate
    assert_not rooms(:pets).active?
  end

  test "active_member_count returns count of active visible members" do
    room = rooms(:watercooler)
    initial_count = room.active_member_count

    # Add a new active user
    new_user = User.create!(name: "New User", email_address: "new@example.com", password: "secret123456")
    room.memberships.grant_to(new_user)

    assert_equal initial_count + 1, room.active_member_count
  end

  test "active_member_count excludes invisible memberships" do
    room = rooms(:watercooler)
    initial_count = room.active_member_count

    # Make a membership invisible
    membership = room.memberships.first
    membership.update!(involvement: :invisible)

    assert_equal initial_count - 1, room.active_member_count
  end

  # System event messages

  test "post_system_message creates a message without triggering callbacks" do
    room = rooms(:pets)
    actor = users(:david)

    assert_no_enqueued_jobs only: Notification::DispatchJob do
      message = room.post_system_message(event: "room_renamed", body: "renamed the room from X to Y", actor: actor)

      assert message.persisted?
      assert_equal "room_renamed", message.event
      assert_equal "renamed the room from X to Y", message.reload.plain_text_body
      assert_equal actor.id, message.creator_id
    end
  end

  test "post_system_message does not touch room last_active_at" do
    room = rooms(:pets)
    original_last_active_at = room.last_active_at

    room.post_system_message(event: "member_joined", body: "added Alice", actor: users(:david))

    assert_equal original_last_active_at, room.reload.last_active_at
  end

  test "post_system_message does not index in search" do
    room = rooms(:pets)

    message = room.post_system_message(event: "member_joined", body: "added Alice", actor: users(:david))

    # insert! bypasses the indexing callbacks, so the message must not reach the
    # search index on either engine — an empty FTS5 shadow row (SQLite) or a null
    # tsvector column (Postgres).
    if Message::SearchIndex.postgresql?
      assert_nil Message.connection.select_value("SELECT body_search FROM messages WHERE id = #{message.id}")
    else
      count = Message.connection.select_value("SELECT count(*) FROM message_search_index WHERE rowid = #{message.id}")
      assert_equal 0, count
    end
  end

  test "announce_rename posts a room_renamed event" do
    room = rooms(:pets)
    room.update!(name: "New Pets")

    message = room.announce_rename("All Pets", actor: users(:david))

    assert_equal "room_renamed", message.event
    assert_equal "renamed the room from All Pets to New Pets", message.reload.plain_text_body
  end

  test "announce_membership_changes posts events for granted and revoked users" do
    room = rooms(:watercooler)
    granted = [ users(:kevin) ]
    revoked = [ users(:jason) ]

    assert_difference -> { Message.unscoped.where(room: room, event: "member_joined").count } do
      assert_difference -> { Message.unscoped.where(room: room, event: "member_left").count } do
        room.announce_membership_changes(granted: granted, revoked: revoked, actor: users(:david))
      end
    end
  end

  test "announce_membership_changes skips when no changes" do
    room = rooms(:watercooler)

    assert_no_difference -> { Message.unscoped.where(room: room).count } do
      room.announce_membership_changes(granted: [], revoked: [], actor: users(:david))
    end
  end

  # add_member! / remove_member! / accept_join!

  test "add_member! grants membership and posts joined event" do
    room = rooms(:designers)
    user = users(:bender)

    assert_difference -> { room.memberships.visible.count } do
      assert_difference -> { Message.unscoped.where(room: room, event: "member_joined").count } do
        room.add_member!(user, actor: users(:david))
      end
    end
  end

  test "remove_member! revokes membership and posts left event" do
    room = rooms(:designers)
    user = users(:jason)

    assert_difference -> { room.memberships.visible.count }, -1 do
      assert_difference -> { Message.unscoped.where(room: room, event: "member_left").count } do
        room.remove_member!(user, actor: users(:david))
      end
    end
  end

  test "accept_join! grants membership and posts joined event" do
    room = rooms(:pets)
    user = users(:kevin)
    room.memberships.where(user: user).update_all(active: false)

    assert_difference -> { Membership.where(room: room, user: user, active: true).count } do
      assert_difference -> { Message.unscoped.where(room: room, event: "member_joined").count } do
        room.accept_join!(user)
      end
    end
  end

  test "accept_leave! makes membership invisible and posts left event" do
    room = rooms(:watercooler)
    user = users(:david)

    assert_difference -> { Message.unscoped.where(room: room, event: "member_left").count } do
      room.accept_leave!(user)
    end

    assert Membership.find_by(room: room, user: user).involved_in_invisible?
  end

  test "accept_leave! raises LastVisibleMemberError for closed rooms with one visible member" do
    room = rooms(:designers)
    visible = room.memberships.visible.to_a
    visible[1..].each { |m| m.update!(involvement: :invisible) }

    assert_raises(Membership::LastVisibleMemberError) do
      room.accept_leave!(visible.first.user)
    end
  end

  # thread-follow cleanup on leave

  test "removing a member from the parent room silences their thread follows" do
    room = rooms(:pets)
    parent = room.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "in", creator: users(:jason)) }
    assert_equal "everything", thread.memberships.find_by(user: users(:jason)).involvement,
      "replying follows the thread at everything"

    perform_enqueued_jobs { room.remove_member!(users(:jason), actor: users(:david)) }

    assert_equal "invisible", thread.memberships.find_by(user: users(:jason)).involvement,
      "an engaged follower's thread membership is silenced when they leave the parent room"
  end

  test "self-leaving the parent room silences the member's thread follows" do
    room = rooms(:pets)
    parent = room.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "in", creator: users(:jason)) }

    perform_enqueued_jobs { room.accept_leave!(users(:jason)) }

    assert_equal "invisible", thread.memberships.find_by(user: users(:jason)).involvement
  end

  test "silencing thread follows on leave is scoped to the leaver" do
    room = rooms(:pets)
    room.memberships.grant_to(users(:kevin))
    parent = room.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "j", creator: users(:jason)) }
    Current.set(user: users(:kevin)) { thread.messages.create!(body: "k", creator: users(:kevin)) }

    perform_enqueued_jobs { room.remove_member!(users(:jason), actor: users(:david)) }

    assert_equal "invisible", thread.memberships.find_by(user: users(:jason)).involvement
    assert_equal "everything", thread.memberships.find_by(user: users(:kevin)).involvement,
      "another member's thread follow is untouched"
  end

  # toggle_access!

  test "toggle_access! returns reloaded room with correct class" do
    room = rooms(:watercooler)
    assert room.closed?

    result = room.toggle_access!(open: true)

    assert_instance_of Rooms::Open, result
    assert_equal room.id, result.id
  end

  test "toggle_access! returns self when already the target type" do
    room = rooms(:pets)
    assert room.open?

    result = room.toggle_access!(open: true)

    assert_equal room.object_id, result.object_id
  end

  # The type invariant behind the access toggle. Controllers scope their lookups
  # too, but the rule lives on the record so no route around them can widen a
  # private conversation's audience.

  test "a direct room can't change its type" do
    direct = rooms(:david_and_kevin)

    assert_not direct.becomes!(Rooms::Open).save
    assert_equal "Rooms::Direct", Room.find(direct.id).type
  end

  test "a chat thread can't change its type" do
    parent = rooms(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:kevin))

    assert_not thread.becomes!(Rooms::Open).save
    assert_equal "Rooms::Thread", Room.find(thread.id).type
  end

  test "a forum can't change its type" do
    forum = rooms(:help_desk)

    assert_not forum.becomes!(Rooms::Closed).save
    assert_equal "Rooms::Forum", Room.find(forum.id).type
  end

  test "open and closed rooms still convert into each other" do
    assert rooms(:pets).becomes!(Rooms::Closed).save
    assert_equal "Rooms::Closed", Room.find(rooms(:pets).id).type

    assert rooms(:designers).becomes!(Rooms::Open).save
    assert_equal "Rooms::Open", Room.find(rooms(:designers).id).type
  end

  test "post_welcome_message creates a welcome message" do
    room = rooms(:hq)
    user = users(:kevin)

    message = room.post_welcome_message(user: user)

    assert message.persisted?
    assert message.welcome?
    assert_not message.event?
    assert_equal user, message.creator
  end

  test "active_member_count excludes inactive users" do
    room = rooms(:watercooler)
    initial_count = room.active_member_count

    # Deactivate a user
    user = room.users.first
    user.update!(status: :deactivated)

    assert_equal initial_count - 1, room.active_member_count
  end

  # bot_memberships_for_events

  test "bot_memberships_for_events returns eligible bots for updates and deletes" do
    room = rooms(:watercooler)
    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-update-1")
    result = room.bot_memberships_for_events(message, :updated)
    assert result.any?, "should deliver updates to eligible bots"
  end

  test "bot_memberships_for_events returns mentioned bots" do
    room = rooms(:watercooler)
    bender = users(:bender)
    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-1")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_events(message, :created)
    assert_includes result.map(&:user_id), bender.id
  end

  test "bot_memberships_for_events excludes muted bots" do
    room = rooms(:watercooler)
    bender = users(:bender)
    bender.memberships.find_by!(room: room).update!(involvement: :nothing)

    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-2")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_events(message, :created)
    assert_empty result
  end

  test "bot_memberships_for_events includes bots without webhook" do
    room = rooms(:watercooler)
    bender = users(:bender)
    bender.webhook.destroy!

    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-3")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_events(message, :created)
    assert_includes result.map(&:user_id), bender.id
  end

  test "bot_memberships_for_events notifies thread bot members without requiring a mention" do
    parent_room = rooms(:watercooler)
    bender = users(:bender)
    parent_message = parent_room.messages.create!(body: "Starting a thread", creator: bender, client_message_id: "wh-thread-1")

    thread = Current.set(user: bender) do
      Rooms::Thread.find_or_create_for(parent_message, creator: bender)
    end
    thread.involve_user(bender, unread: false)

    message = thread.messages.create!(body: "Follow-up from user", creator: users(:david), client_message_id: "wh-thread-2")
    message.stubs(:mentionees).returns(User.none)

    result = thread.bot_memberships_for_events(message, :created)
    assert_includes result.map(&:user_id), bender.id, "bot in a thread should receive message events even without a mention"
  end

  # The tests below pin observable Room callback behavior: the shared
  # room-list stream broadcasts on sortable_name change, sidebar appends to each visible member
  # on reactivation (suppressed for thread rooms), and the room_created event
  # message posted on creation (suppressed for direct and thread rooms). They
  # assert what the callbacks emit, not how they're wired, so they survive
  # moves between the model and concerns.

  test "renaming a room broadcasts to the shared room-list stream" do
    room = rooms(:pets)
    ActionCable.server.pubsub.clear

    assert_broadcasts(Account.sole.room_list_stream_name, 1) do
      room.update!(name: "Other Pets")
    end
  end

  test "updating a room without changing its name does not broadcast to the room-list stream" do
    room = rooms(:pets)
    room.save!  # ensure sortable_name is materialized (fixtures bypass callbacks)
    ActionCable.server.pubsub.clear

    assert_no_broadcasts(Account.sole.room_list_stream_name) do
      room.update!(last_active_at: 1.second.from_now)
    end
  end

  test "receiving a message publishes one shared nudge, not one per member" do
    room = rooms(:watercooler)
    members = room.memberships.visible.includes(:user).map(&:user)
    assert members.size >= 2, "fixture should have multiple members for this test to be meaningful"
    ActionCable.server.pubsub.clear

    assert_broadcasts(Account.sole.room_list_stream_name, 1) do
      room.messages.create!(body: "Hello all", creator: members.first, client_message_id: SecureRandom.uuid)
    end

    members.each do |user|
      assert_empty ActionCable.server.pubsub.broadcasts(ReadRoomsChannel.broadcasting_for(user)),
        "the send path should not push per-member unread broadcasts"
    end
  end

  test "reactivating a sidebar room broadcasts an append to each visible member's sidebar" do
    room = rooms(:pets)
    room.update_columns(active: false)
    visible = room.memberships.visible.includes(:user).to_a
    assert visible.size >= 2, "fixture should have multiple visible members for this test to be meaningful"
    ActionCable.server.pubsub.clear

    room.activate!

    visible.each do |membership|
      assert_rendered_turbo_stream_broadcast membership.user, :rooms,
        action: "append", target: membership.sidebar_list_name
    end
  end

  test "non-active updates do not broadcast a reactivation" do
    room = rooms(:pets)
    user = room.memberships.visible.first.user
    ActionCable.server.pubsub.clear

    room.update!(last_active_at: 1.second.from_now)

    stream_name = "#{user.to_gid_param}:rooms"
    assert_empty ActionCable.server.pubsub.broadcasts(stream_name),
      "non-active updates should not emit sidebar reactivation broadcasts"
  end

  test "reactivating a thread room does not broadcast sidebar appends" do
    parent = rooms(:pets).messages.create!(creator: users(:david), body: "Parent",
                                            client_message_id: "thread_reactivate_skip_sidebar")
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread.update_columns(active: false)
    ActionCable.server.pubsub.clear

    thread.activate!

    stream_name = "#{users(:david).to_gid_param}:rooms"
    assert_empty ActionCable.server.pubsub.broadcasts(stream_name),
      "thread room reactivation should not emit sidebar broadcasts (sidebar_room? guard)"
  end

  test "creating a non-direct, non-thread room with an audience posts a room_created event" do
    assert_difference -> { Message.unscoped.where(event: "room_created").count }, 1 do
      Rooms::Open.create!(name: "Greenhouse", creator: users(:david))
    end
  end

  test "creating a direct room does not post a room_created event" do
    Current.set(user: users(:david)) do
      assert_no_difference -> { Message.unscoped.where(event: "room_created").count } do
        Rooms::Direct.find_or_create_for([ users(:david), users(:bender) ])
      end
    end
  end

  test "creating a thread room does not post a room_created event" do
    parent = rooms(:pets).messages.create!(creator: users(:david), body: "Parent",
                                            client_message_id: "thread_create_no_event")

    # Don't scope to parent's room — if announce_creation fired on the thread,
    # the room_created message would have room_id = thread.id, not parent.room_id.
    assert_no_difference -> { Message.unscoped.where(event: "room_created").count } do
      Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    end
  end
end
