require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "last_active_at is set on room creation" do
    room = Rooms::Open.create!(name: "New Room", creator: users(:david))
    assert room.last_active_at.present?
    assert_in_delta Time.current, room.last_active_at, 2.seconds
  end

  test "grant membership to user" do
    rooms(:watercooler).memberships.grant_to(users(:kevin))
    assert rooms(:watercooler).users.include?(users(:kevin))
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

  test "type" do
    assert Rooms::Open.new.open?
    assert_not Rooms::Open.new.direct?
    assert Rooms::Direct.new.direct?
    assert Rooms::Closed.new.closed?
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

    assert_no_enqueued_jobs only: Room::PushMessageJob do
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
    results = Message.connection.execute("SELECT count(*) FROM message_search_index WHERE rowid = #{message.id}")

    assert_equal 0, results.first.values.first
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

  # bot_memberships_for_webhook

  test "bot_memberships_for_webhook returns eligible bots for updates and deletes" do
    room = rooms(:watercooler)
    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-update-1")
    result = room.bot_memberships_for_webhook(message, :updated)
    assert result.any?, "should deliver updates to eligible bots"
  end

  test "bot_memberships_for_webhook returns mentioned bots" do
    room = rooms(:watercooler)
    bender = users(:bender)
    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-1")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_webhook(message, :created)
    assert_includes result.map(&:user_id), bender.id
  end

  test "bot_memberships_for_webhook excludes muted bots" do
    room = rooms(:watercooler)
    bender = users(:bender)
    bender.memberships.find_by!(room: room).update!(involvement: :nothing)

    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-2")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_webhook(message, :created)
    assert_empty result
  end

  test "bot_memberships_for_webhook excludes bots without webhook" do
    room = rooms(:watercooler)
    bender = users(:bender)
    bender.webhook.destroy!

    message = room.messages.create!(body: "Hey", creator: users(:david), client_message_id: "wh-test-3")
    message.stubs(:mentionees).returns(User.where(id: bender.id))

    result = room.bot_memberships_for_webhook(message, :created)
    assert_empty result
  end
end
