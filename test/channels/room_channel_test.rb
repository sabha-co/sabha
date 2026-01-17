require "test_helper"

class RoomChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
  end

  test "subscribes to a room the user is a member of" do
    room = users(:david).rooms.first

    subscribe room_id: room.id

    assert subscription.confirmed?
    assert_has_stream_for room
  end

  test "rejects subscription to a room the user is not a member of" do
    other_room = Rooms::Closed.create!(name: "Secret Room", creator: users(:jason))

    subscribe room_id: other_room.id

    assert subscription.rejected?
  end

  test "rejects subscription without room_id" do
    subscribe

    assert subscription.rejected?
  end

  test "rejects subscription with invalid room_id" do
    subscribe room_id: -1

    assert subscription.rejected?
  end
end
