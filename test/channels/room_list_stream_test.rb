require "test_helper"

# The sidebar's room-list stream is a signed pub/sub stream: the client
# subscribes with a server-minted signed name (no per-subscriber channel
# authorization), so the signature is the whole access control. These tests
# pin that contract — a valid signature streams, anything else is rejected.
class RoomListStreamTest < ActionCable::Channel::TestCase
  tests AnyCable::Rails::PubSubChannel

  test "the account's signed stream name subscribes to the room-list stream" do
    subscribe signed_stream_name: Account.sole.signed_room_list_stream_name

    assert subscription.confirmed?
    assert_has_stream Account.sole.room_list_stream_name
  end

  test "a tampered stream name is rejected" do
    subscribe signed_stream_name: Account.sole.signed_room_list_stream_name + "0"

    assert subscription.rejected?
  end

  test "an unsigned stream name is rejected" do
    stub_connection
    def connection.allow_public_streams? = false

    subscribe stream_name: Account.sole.room_list_stream_name

    assert subscription.rejected?
  end
end
