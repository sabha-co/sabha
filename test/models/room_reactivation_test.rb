require "test_helper"

class RoomReactivationTest < ActiveSupport::TestCase
  setup do
    @room = Rooms::Open.create!(name: "Test Room", creator: users(:david))
    @room.memberships.grant_to(users(:david))
    @room.memberships.grant_to(users(:jason))
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
end
