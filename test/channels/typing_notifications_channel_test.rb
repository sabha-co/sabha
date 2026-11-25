require "test_helper"

class TypingNotificationsChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection(current_user: users(:david))
    @channel = users(:david).channels.first
  end

  test "subscribes to a channel" do
    subscribe channel_id: @channel.id

    assert subscription.confirmed?
    assert_has_stream_for @channel
  end

  test "broadcasts start typing notification" do
    subscribe channel_id: @channel.id

    assert_broadcast_on(@channel, action: :start, user: { id: users(:david).id, name: users(:david).name }) do
      perform :start
    end
  end

  test "broadcasts stop typing notification" do
    subscribe channel_id: @channel.id

    assert_broadcast_on(@channel, action: :stop, user: { id: users(:david).id, name: users(:david).name }) do
      perform :stop
    end
  end

  test "rejects subscription to a channel user is not a member of" do
    other_channel = Channels::Closed.create!(name: "Secret Channel", creator: users(:jason))

    subscribe channel_id: other_channel.id

    assert subscription.rejected?
  end

  # A forum post derives access from its forum, so a member can type in a post
  # they haven't followed — no per-post membership row. Without the derived-access
  # fallback in ChannelScopedChannel#find_channel, the typing channel rejected them.
  test "a forum member without a post membership can subscribe to a post" do
    forum = Channels::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    member = users(:kevin) # auto-joined to the forum, no post membership
    assert_not Membership.exists?(channel_id: post.id, user_id: member.id)

    stub_connection(current_user: member)
    subscribe channel_id: post.id

    assert subscription.confirmed?
    assert_has_stream_for post
  end

  test "a non-forum-member is rejected from a post" do
    forum = Channels::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    outsider = users(:jason)
    forum.remove_member!(outsider, actor: users(:david)) # auto-joined, then removed

    stub_connection(current_user: outsider)
    subscribe channel_id: post.id

    assert subscription.rejected?
  end

  # A chat thread derives access from the channel it was spawned in, so a parent-channel
  # member can type in a thread they never posted in — no per-thread membership.
  test "a parent-channel member without a thread membership can subscribe to a thread" do
    parent = users(:david).channels.first
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Channels::Thread.find_or_create_for(parent_message, creator: users(:david))
    member = parent.users.excluding(users(:david)).first
    assert_not Membership.exists?(channel_id: thread.id, user_id: member.id),
      "precondition: the member has no thread membership"

    stub_connection(current_user: member)
    subscribe channel_id: thread.id

    assert subscription.confirmed?
    assert_has_stream_for thread
  end

  # A member removed from the parent channel keeps a silenced-but-active thread
  # membership (follows are silenced, not deactivated). That stale row must not
  # keep granting channel access after they lose parent access.
  test "a member removed from the parent channel is rejected from a thread despite a silenced membership" do
    parent = Channels::Closed.create!(name: "War Channel", creator: users(:david))
    parent.memberships.grant_to([ users(:david), users(:jason) ])
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Channels::Thread.find_or_create_for(parent_message, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "in", creator: users(:jason)) }

    perform_enqueued_jobs { parent.remove_member!(users(:jason), actor: users(:david)) }
    assert Membership.exists?(channel_id: thread.id, user_id: users(:jason).id, active: true),
      "precondition: the silenced thread membership is still active"

    stub_connection(current_user: users(:jason))
    subscribe channel_id: thread.id

    assert subscription.rejected?
  end

  test "a non-member of the parent channel is rejected from a thread" do
    parent = users(:david).channels.first
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Channels::Thread.find_or_create_for(parent_message, creator: users(:david))
    outsider = User.where.not(id: parent.users.select(:id)).active.first

    stub_connection(current_user: outsider)
    subscribe channel_id: thread.id

    assert subscription.rejected?
  end

  test "start and stop handle nil @channel gracefully (AnyCable HTTP RPC scenario)" do
    # In AnyCable HTTP RPC mode, @channel isn't preserved between calls.
    # Simulate this by creating a fresh channel instance and calling actions directly.
    subscribe channel_id: @channel.id

    # Simulate AnyCable's stateless RPC by clearing @channel
    subscription.instance_variable_set(:@channel, nil)

    # These should not raise errors
    assert_nothing_raised do
      perform :start
      perform :stop
    end
  end
end
