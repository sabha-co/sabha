require "test_helper"

class ChannelReactivationTest < ActiveSupport::TestCase
  setup do
    @channel = Channels::Open.create!(name: "Test Channel", creator: users(:david))
    @channel.memberships.grant_to(users(:david))
    @channel.memberships.grant_to(users(:jason))
  end

  test "deactivate sets channel memberships to inactive" do
    initial_count = @channel.memberships.active.count
    assert initial_count > 0

    @channel.deactivate

    assert_equal 0, @channel.memberships.active.count
    assert_equal initial_count, @channel.memberships.rewhere(active: false).count
  end

  test "deactivate sets channel messages to inactive" do
    message1 = @channel.messages.create!(body: "Message 1", creator: users(:david))
    message2 = @channel.messages.create!(body: "Message 2", creator: users(:jason))

    @channel.deactivate

    assert_not message1.reload.active?
    assert_not message2.reload.active?
  end

  test "deactivate also deactivates thread channels" do
    message = @channel.messages.create!(body: "Parent message", creator: users(:david))
    thread = Channels::Thread.create!(parent_message: message, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread_message = thread.messages.create!(body: "Thread message", creator: users(:david))

    @channel.deactivate

    assert_not thread.reload.active?
    assert_not thread_message.reload.active?
    assert_equal 0, thread.memberships.active.count
  end

  test "reactivate sets channel to active" do
    @channel.deactivate
    @channel.reactivate

    assert @channel.reload.active?
  end

  test "reactivate sets channel memberships to active" do
    initial_count = @channel.memberships.count

    @channel.deactivate
    assert_equal 0, @channel.memberships.active.count

    @channel.reactivate
    assert_equal initial_count, @channel.memberships.active.count
  end

  test "reactivate sets channel messages to active" do
    message1 = @channel.messages.create!(body: "Message 1", creator: users(:david))
    message2 = @channel.messages.create!(body: "Message 2", creator: users(:jason))

    @channel.deactivate
    @channel.reactivate

    assert message1.reload.active?
    assert message2.reload.active?
  end

  test "reactivate also reactivates thread channels" do
    message = @channel.messages.create!(body: "Parent message", creator: users(:david))
    thread = Channels::Thread.create!(parent_message: message, creator: users(:david))
    thread.memberships.grant_to(users(:david))
    thread_message = thread.messages.create!(body: "Thread message", creator: users(:david))

    @channel.deactivate
    assert_not thread.reload.active?

    @channel.reactivate

    assert thread.reload.active?
    assert thread_message.reload.active?
    assert message.reload.active?
    assert thread.memberships.active.count > 0
  end

  test "deactivate and reactivate preserve membership involvement" do
    membership = @channel.memberships.find_by(user: users(:david))
    membership.update!(involvement: "everything")

    @channel.deactivate
    @channel.reactivate

    assert_equal "everything", membership.reload.involvement
  end
end
