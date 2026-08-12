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
end
