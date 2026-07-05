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

  # A forum post derives access from its forum, so a member can type in a post
  # they haven't followed — no per-post membership row. Without the derived-access
  # fallback in RoomChannel#find_room, the typing channel rejected them.
  test "a forum member without a post membership can subscribe to a post" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    member = users(:kevin) # auto-joined to the forum, no post membership
    assert_not Membership.exists?(room_id: post.id, user_id: member.id)

    stub_connection(current_user: member)
    subscribe room_id: post.id

    assert subscription.confirmed?
    assert_has_stream_for post
  end

  test "a non-forum-member is rejected from a post" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    outsider = users(:jason)
    forum.remove_member!(outsider, actor: users(:david)) # auto-joined, then removed

    stub_connection(current_user: outsider)
    subscribe room_id: post.id

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
