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

  test "cannot merge the original room into another" do
    assert_raises(Room::CannotDeleteOriginalError) { rooms(:hq).merge_into!(rooms(:pets)) }
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

  test "active_member_count excludes inactive users" do
    room = rooms(:watercooler)
    initial_count = room.active_member_count

    # Deactivate a user
    user = room.users.first
    user.update!(status: :deactivated)

    assert_equal initial_count - 1, room.active_member_count
  end
end
