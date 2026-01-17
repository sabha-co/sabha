require "test_helper"

class HeartbeatChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
  end

  test "subscribes successfully" do
    subscribe

    assert subscription.confirmed?
  end
end
