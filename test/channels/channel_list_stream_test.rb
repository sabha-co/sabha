require "test_helper"

# The sidebar's channel-list stream is a signed pub/sub stream: the client
# subscribes with a server-minted signed name (no per-subscriber channel
# authorization), so the signature is the whole access control. These tests
# pin that contract — a valid signature streams, anything else is rejected.
class ChannelListStreamTest < ActionCable::Channel::TestCase
  tests AnyCable::Rails::PubSubChannel

  test "the account's signed stream name subscribes to the channel-list stream" do
    subscribe signed_stream_name: Account.sole.signed_channel_list_stream_name

    assert subscription.confirmed?
    assert_has_stream Account.sole.channel_list_stream_name
  end

  test "a tampered stream name is rejected" do
    subscribe signed_stream_name: Account.sole.signed_channel_list_stream_name + "0"

    assert subscription.rejected?
  end

  test "an unsigned stream name is rejected" do
    stub_connection
    def connection.allow_public_streams? = false

    subscribe stream_name: Account.sole.channel_list_stream_name

    assert subscription.rejected?
  end
end
