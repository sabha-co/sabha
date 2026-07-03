require "test_helper"

class Rooms::ForumTest < ActiveSupport::TestCase
  test "create_for makes a forum and grants creator membership" do
    forum = Rooms::Forum.create_for({ name: "Support", creator: users(:david) }, users: users(:david))

    assert forum.persisted?
    assert forum.forum?
    assert_includes forum.users, users(:david)
  end

  test "joining or renaming a forum writes no orphaned system message" do
    forum = rooms(:help_desk)

    assert_no_difference -> { Message.where(room_id: forum.id).count } do
      forum.accept_join!(users(:jason))
      forum.announce_rename("Old name", actor: users(:david))
    end
  end

  test "an opening post does not bump the forum's activity (no chat-counter reorder)" do
    forum = rooms(:help_desk)
    before = forum.last_active_at

    travel_to 3.hours.from_now do
      create_forum_post(title: "Fresh post", forum: forum)
    end

    assert_equal before.to_i, forum.reload.last_active_at.to_i
  end

  test "type predicates place a forum among sidebar rooms, not threads or directs" do
    forum = rooms(:help_desk)

    assert forum.forum?
    assert forum.sidebar_room?
    assert_not forum.thread?
    assert_not forum.direct?
    assert_not forum.open?
    assert_not forum.closed?
  end

  test "forums scope returns only forums" do
    assert_includes Room.forums, rooms(:help_desk)
    assert_not_includes Room.forums, rooms(:hq)
  end

  test "a forum is joinable, so the last-visible-member gate does not apply" do
    forum = rooms(:help_desk)

    # Open/forum rooms return early from the gate the way leaving a closed room would not.
    assert_nothing_raised do
      forum.ensure_visible_members_remain!(excluding: [ users(:david).id ])
    end
  end

  test "an opening post never pings everyone in the forum" do
    forum = rooms(:help_desk)
    message = forum.messages.create!(body: "How do I configure webhooks?", creator: users(:david))

    types = forum.applicable_activity_types(message)

    assert_empty types
    assert_not_includes types, :everyone_room_message
  end

  test "membership shared scope includes forum memberships" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    membership = Membership.find_by(room: forum, user: users(:jason))

    assert_includes Membership.shared, membership
  end

  # --- Cascade & reactivation correctness (U4) --------------------------------

  test "restoring a forum restores posts that were active when it was deleted" do
    forum = rooms(:help_desk)
    post = create_forum_post

    forum.deactivate
    assert post.reload.deactivated?

    forum.reactivate
    assert post.reload.active?
  end

  test "restoring a forum does not resurrect a post that was individually deleted first" do
    forum = rooms(:help_desk)
    kept = create_forum_post(title: "Still open")
    removed = create_forum_post(title: "Deleted on its own")

    removed.deactivate
    assert removed.reload.deactivated?, "the post should be deleted on its own"

    forum.deactivate
    forum.reactivate

    assert kept.reload.active?, "a post active at forum-delete time should return"
    assert removed.reload.deactivated?, "an individually-deleted post must stay deleted (R15)"
  end

  test "a cascade-deactivated post carries the marker; a self-deleted post does not" do
    forum = rooms(:help_desk)
    self_deleted = create_forum_post(title: "self")
    cascaded = create_forum_post(title: "cascade")

    self_deleted.deactivate
    forum.deactivate

    assert_not self_deleted.reload.cascade_deactivated?, "self-delete must not set the cascade marker"
    assert cascaded.reload.cascade_deactivated?, "cascade delete must set the marker"
  end

  test "the cascade marker is cleared when a post is restored" do
    forum = rooms(:help_desk)
    post = create_forum_post

    forum.deactivate
    assert post.reload.cascade_deactivated?

    forum.reactivate
    assert_not post.reload.cascade_deactivated?
  end

  test "hard-deleting a forum removes its posts (R16)" do
    forum = rooms(:help_desk)
    post = create_forum_post

    assert_nothing_raised { forum.destroy }

    assert_not Rooms::Thread.exists?(post.id)
  end

  # --- Review-hardening -------------------------------------------------------

  test "an opening post that mentions a member routes a mention activity type" do
    forum = rooms(:help_desk)
    message = forum.messages.create!(body: "Ping", creator: users(:david))
    message.stubs(:mentionees).returns([ users(:jason) ])

    assert_includes forum.applicable_activity_types(message), :mention
  end

  test "deleting a post's opening message deactivates the post-thread (no zombie)" do
    forum = rooms(:help_desk)
    post = create_forum_post(title: "Doomed")
    assert post.active?

    post.parent_message.deactivate

    assert post.reload.deactivated?, "the post-thread should be deactivated with its opening message"
    assert_not_includes forum.posts, post
  end
end
