require "test_helper"

class Inbox::ThreadsQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:jason)
    @parent_room = rooms(:hq)
    @parent_message = @parent_room.messages.create!(body: "Parent", creator: users(:david), client_message_id: "tq-parent")
    @thread = Rooms::Thread.find_or_create_for(@parent_message, creator: @user)
    @thread.messages.create!(body: "Reply", creator: @user, client_message_id: "tq-reply")
  end

  test "returns the parent message of an accessible active thread" do
    assert_includes Inbox::ThreadsQuery.new(@user).call, @parent_message
  end

  test "excludes a deactivated thread (active = TRUE boolean holds on every adapter)" do
    @thread.update!(active: false)

    assert_not_includes Inbox::ThreadsQuery.new(@user).call, @parent_message
  end

  test "unseen_reply_counts counts a follower's unread replies and skips non-members" do
    parent = @parent_room.messages.create!(body: "P", creator: users(:david), client_message_id: "uc-parent")
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    follower = users(:kevin)
    thread.memberships.grant_to(follower) # cursor snapshots here, before any replies

    thread.messages.create!(body: "r1", creator: users(:david), client_message_id: "uc-r1")
    thread.messages.create!(body: "r2", creator: users(:david), client_message_id: "uc-r2")

    assert_equal({ thread.id => 2 }, Inbox::ThreadsQuery.unseen_reply_counts(follower, [ parent ]))
    assert_equal({}, Inbox::ThreadsQuery.unseen_reply_counts(users(:jz), [ parent ]))
  end

  test "followed_thread_room_ids returns the follower's thread rooms and skips non-members" do
    assert_equal Set[@thread.id], Inbox::ThreadsQuery.followed_thread_room_ids(@user, [ @parent_message ])
    assert_equal Set.new, Inbox::ThreadsQuery.followed_thread_room_ids(users(:jz), [ @parent_message ])
  end

  test "followed_thread_room_ids excludes an invisible (left) membership" do
    @thread.memberships.find_by(user: @user).update!(involvement: :invisible)

    assert_equal Set.new, Inbox::ThreadsQuery.followed_thread_room_ids(@user, [ @parent_message ])
  end

  test "followed_thread_room_ids batches the follow lookup into one query" do
    messages = Inbox::ThreadsQuery.new(@user).call.to_a

    assert_queries_count 1 do
      Inbox::ThreadsQuery.followed_thread_room_ids(@user, messages)
    end
  end

  test "call preloads thread creators so cards render without an N+1" do
    messages = Inbox::ThreadsQuery.new(@user).call.to_a

    assert_no_queries do
      messages.each { |m| m.threads.each(&:creator) }
    end
  end

  test "count returns the number of accessible thread parents" do
    assert_equal Inbox::ThreadsQuery.new(@user).call.to_a.size, Inbox::ThreadsQuery.new(@user).count
  end
end
