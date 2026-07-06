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

  # A chat thread derives access from the room it was spawned in, so a parent-room
  # member can type in a thread they never posted in — no per-thread membership.
  test "a parent-room member without a thread membership can subscribe to a thread" do
    parent = users(:david).rooms.first
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent_message, creator: users(:david))
    member = parent.users.excluding(users(:david)).first
    assert_not Membership.exists?(room_id: thread.id, user_id: member.id),
      "precondition: the member has no thread membership"

    stub_connection(current_user: member)
    subscribe room_id: thread.id

    assert subscription.confirmed?
    assert_has_stream_for thread
  end

  # A member removed from the parent room keeps a silenced-but-active thread
  # membership (follows are silenced, not deactivated). That stale row must not
  # keep granting channel access after they lose parent access.
  test "a member removed from the parent room is rejected from a thread despite a silenced membership" do
    parent = Rooms::Closed.create!(name: "War Room", creator: users(:david))
    parent.memberships.grant_to([ users(:david), users(:jason) ])
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent_message, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "in", creator: users(:jason)) }

    perform_enqueued_jobs { parent.remove_member!(users(:jason), actor: users(:david)) }
    assert Membership.exists?(room_id: thread.id, user_id: users(:jason).id, active: true),
      "precondition: the silenced thread membership is still active"

    stub_connection(current_user: users(:jason))
    subscribe room_id: thread.id

    assert subscription.rejected?
  end

  test "a non-member of the parent room is rejected from a thread" do
    parent = users(:david).rooms.first
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent_message, creator: users(:david))
    outsider = User.where.not(id: parent.users.select(:id)).active.first

    stub_connection(current_user: outsider)
    subscribe room_id: thread.id

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
