require "test_helper"

class ChannelScopedChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
  end

  test "subscribes to a channel the user is a member of" do
    channel = users(:david).channels.first

    subscribe channel_id: channel.id

    assert subscription.confirmed?
    assert_has_stream_for channel
  end

  test "rejects subscription to a channel the user is not a member of" do
    other_channel = Channels::Closed.create!(name: "Secret Channel", creator: users(:jason))

    subscribe channel_id: other_channel.id

    assert subscription.rejected?
  end

  test "rejects subscription without channel_id" do
    subscribe

    assert subscription.rejected?
  end
end
