require "test_helper"

class RoomReactivationTest < ActiveSupport::TestCase
  setup do
    @room = Rooms::Open.create!(name: "Test Room", creator: users(:david))
    @room.memberships.grant_to(users(:david))
    @room.memberships.grant_to(users(:jason))
  end

  test "deactivate sets room to inactive" do
    @room.deactivate
    assert_not @room.reload.active?
  end

  test "deactivate sets room memberships to inactive" do
    initial_count = @room.memberships.active.count
    assert initial_count > 0

    @room.deactivate

    assert_equal 0, @room.memberships.active.count
    assert_equal initial_count, @room.memberships.rewhere(active: false).count
  end

  test "deactivate sets room messages to inactive" do
    message1 = @room.messages.create!(body: "Message 1", creator: users(:david))
    message2 = @room.messages.create!(body: "Message 2", creator: users(:jason))

    @room.deactivate

    assert_not message1.reload.active?
    assert_not message2.reload.active?
  end

  test "deactivate also deactivates thread rooms" do
    message = @room.messages.create!(body: "Parent message", creator: users(:david))
    thread = Rooms::Thread.create!(parent_message: message, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread_message = thread.messages.create!(body: "Thread message", creator: users(:david))

    @room.deactivate

    assert_not thread.reload.active?
    assert_not thread_message.reload.active?
    assert_equal 0, thread.memberships.active.count
  end

  test "reactivate sets room to active" do
    @room.deactivate
    @room.reactivate

    assert @room.reload.active?
  end

  test "reactivate sets room memberships to active" do
    initial_count = @room.memberships.count

    @room.deactivate
    assert_equal 0, @room.memberships.active.count

    @room.reactivate
    assert_equal initial_count, @room.memberships.active.count
  end

  test "reactivate sets room messages to active" do
    message1 = @room.messages.create!(body: "Message 1", creator: users(:david))
    message2 = @room.messages.create!(body: "Message 2", creator: users(:jason))

    @room.deactivate
    @room.reactivate

    assert message1.reload.active?
    assert message2.reload.active?
  end

  test "reactivate also reactivates thread rooms" do
    message = @room.messages.create!(body: "Parent message", creator: users(:david))
    thread = Rooms::Thread.create!(parent_message: message, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread_message = thread.messages.create!(body: "Thread message", creator: users(:david))

    @room.deactivate
    assert_not thread.reload.active?

    @room.reactivate

    assert thread.reload.active?
    assert thread_message.reload.active?
    assert message.reload.active?
    assert thread.memberships.active.count > 0
  end

  test "deactivate and reactivate preserve membership involvement" do
    membership = @room.memberships.find_by(user: users(:david))
    membership.update!(involvement: "everything")

    @room.deactivate
    @room.reactivate

    assert_equal "everything", membership.reload.involvement
  end

  test "merge_into deactivates source room" do
    target_room = Rooms::Open.create!(name: "Target Room", creator: users(:david))
    target_room.memberships.grant_to(users(:david))

    @room.merge_into!(target_room)

    assert_not @room.reload.active?
  end

  test "merge_into moves messages to target room" do
    target_room = Rooms::Open.create!(name: "Target Room", creator: users(:david))
    target_room.memberships.grant_to(users(:david))

    message = @room.messages.create!(body: "Test message", creator: users(:david))

    @room.merge_into!(target_room)

    assert_equal target_room.id, message.reload.room_id
  end

  test "merge_into deactivates source memberships" do
    target_room = Rooms::Open.create!(name: "Target Room", creator: users(:david))
    target_room.memberships.grant_to(users(:david))

    assert @room.memberships.active.count > 0

    @room.merge_into!(target_room)

    assert_equal 0, @room.memberships.active.count
  end

  test "merge_into moves inactive messages to target room" do
    target_room = Rooms::Open.create!(name: "Target Room", creator: users(:david))
    target_room.memberships.grant_to(users(:david))

    active_message = @room.messages.create!(body: "Active message", creator: users(:david))
    inactive_message = @room.messages.create!(body: "Inactive message", creator: users(:david))
    inactive_message.deactivate!

    @room.merge_into!(target_room)

    assert_equal target_room.id, active_message.reload.room_id
    assert_equal target_room.id, inactive_message.reload.room_id
  end

  test "merge_into updates counter caches" do
    target_room = Rooms::Open.create!(name: "Target Room", creator: users(:david))
    target_room.memberships.grant_to(users(:david))

    3.times { @room.messages.create!(body: "Test", creator: users(:david)) }
    2.times { target_room.messages.create!(body: "Test", creator: users(:david)) }

    initial_source_count = @room.reload.messages_count
    initial_target_count = target_room.reload.messages_count

    assert_equal 3, initial_source_count
    assert_equal 2, initial_target_count

    @room.merge_into!(target_room)

    assert_equal 0, @room.reload.messages_count
    assert_equal 5, target_room.reload.messages_count
  end
end
