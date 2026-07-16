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

  test "presenting joins the room's own presence stream" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    subscription.expects(:join_presence).with(PresenceChannel.broadcasting_for(membership.room))
    subscription.present
  end

  test "going absent leaves the presence set" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    subscription.expects(:leave_presence)
    subscription.absent
  end

  test "unsubscribing does not leave presence — AnyCable auto-removes on unsubscribe, an explicit leave races the stream teardown" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    subscription.expects(:leave_presence).never
    unsubscribe
  end

  # One subscription contributes one connection, so it may only take one away.
  # A hidden tab sends `absent`; closing it then fires unsubscribe as well, and
  # the second decrement would come out of another tab's count — marking a room
  # unread while the member is still sitting in it.
  test "a hidden tab that then closes gives back exactly one connection" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id
    membership.reload.present # a second tab
    assert_equal 2, membership.reload.connections

    subscription.absent
    unsubscribe

    assert_equal 1, membership.reload.connections, "the second tab's connection must survive"
    assert membership.connected?
  end

  # The two tests above can't see this. Under AnyCable every command is its own
  # RPC against a fresh channel object, so the guard only survives from `absent`
  # to `depart` if it's registered channel state — but the ActionCable test
  # adapter reuses one instance, where a plain attr_accessor passes both of them
  # while silently double-decrementing in production. Pin the mechanism itself.
  test "the departure guard is channel state, so it survives the RPC boundary" do
    assert_includes PresenceChannel.channel_state_attributes, :departed,
      "a plain instance variable is gone by the next RPC, so `depart` would decrement a second time"
  end

  test "presenting again after going absent re-arms the departure guard" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    subscription.absent
    subscription.present # tab visible again
    unsubscribe          # …and now it really closes

    assert_equal 0, membership.reload.connections
  end

  test "presence is keyed by the user id so a member's tabs dedupe to one entry" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    assert_equal users(:david).id, subscription.send(:user_presence_id)
  end

  test "the presence stream matches the room's subscription stream" do
    membership = users(:david).memberships.first
    subscribe room_id: membership.room_id

    assert_has_stream PresenceChannel.broadcasting_for(membership.room)
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
