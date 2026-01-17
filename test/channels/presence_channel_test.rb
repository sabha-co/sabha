require "test_helper"

class PresenceChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
  end

  test "subscribes" do
    room = users(:david).rooms.first

    subscribe room_id: room.id

    assert subscription.confirmed?
    assert_has_stream_for room
  end

  test "rejects subscription to a room that the user is not a member of" do
    subscribe room_id: Rooms::Closed.create!(name: "New Room", creator: users(:david)).id

    assert subscription.rejected?
  end

  test "rejects subscription to non-existent room" do
    subscribe room_id: -1

    assert subscription.rejected?
  end

  test "rejects subscription without a room" do
    subscribe room_id: -1

    assert subscription.rejected?
  end

  test "subscribing marks the membership as connected" do
    membership = users(:david).memberships.first

    assert_changes -> { membership.reload.connected? }, from: false, to: true do
      subscribe room_id: membership.room_id
    end
  end

  test "unsubscribing marks the membership as disconnected" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    assert_changes -> { membership.reload.connected? }, from: true, to: false do
      unsubscribe
    end
  end

  test "absent handles nil @room gracefully (AnyCable HTTP RPC scenario)" do
    # In AnyCable HTTP RPC mode, @room isn't preserved between calls.
    # Simulate this by creating a fresh channel instance and calling absent directly.
    membership = users(:david).memberships.first

    # First subscribe to set up the membership as connected
    subscribe room_id: membership.room_id
    assert membership.reload.connected?

    # Simulate AnyCable's stateless RPC by clearing @room
    subscription.instance_variable_set(:@room, nil)

    # This should not raise an error
    assert_nothing_raised do
      subscription.absent
    end
  end
end
