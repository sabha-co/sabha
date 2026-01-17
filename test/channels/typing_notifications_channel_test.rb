require "test_helper"

class TypingNotificationsChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
    @room = users(:david).rooms.first
  end

  test "subscribes to a room" do
    subscribe room_id: @room.id

    assert subscription.confirmed?
    assert_has_stream_for @room
  end

  test "broadcasts start typing notification" do
    subscribe room_id: @room.id

    assert_broadcast_on(@room, action: :start, user: { id: users(:david).id, name: users(:david).name }) do
      perform :start
    end
  end

  test "broadcasts stop typing notification" do
    subscribe room_id: @room.id

    assert_broadcast_on(@room, action: :stop, user: { id: users(:david).id, name: users(:david).name }) do
      perform :stop
    end
  end

  test "rejects subscription to a room user is not a member of" do
    other_room = Rooms::Closed.create!(name: "Secret Room", creator: users(:jason))

    subscribe room_id: other_room.id

    assert subscription.rejected?
  end

  test "start and stop handle nil @room gracefully (AnyCable HTTP RPC scenario)" do
    # In AnyCable HTTP RPC mode, @room isn't preserved between calls.
    # Simulate this by creating a fresh channel instance and calling actions directly.
    subscribe room_id: @room.id

    # Simulate AnyCable's stateless RPC by clearing @room
    subscription.instance_variable_set(:@room, nil)

    # These should not raise errors
    assert_nothing_raised do
      perform :start
      perform :stop
    end
  end
end
