require "test_helper"

class Rooms::ForumTest < ActiveSupport::TestCase
  test "create_for makes a forum and grants creator membership" do
    forum = Rooms::Forum.create_for({ name: "Support", creator: users(:david) }, users: users(:david))

    assert forum.persisted?
    assert forum.forum?
    assert_includes forum.users, users(:david)
  end

  test "a forum forces auto_join on and adds every active user on create" do
    forum = Rooms::Forum.create_for({ name: "Community", creator: users(:david) }, users: users(:david))

    assert forum.auto_join?
    assert_equal User.active.to_set, forum.reload.users.to_set
  end

  test "a new user is auto-joined to existing forums" do
    forum = Rooms::Forum.create_for({ name: "Community", creator: users(:david) }, users: users(:david))

    newcomer = User.create!(name: "Newcomer", email_address: "newcomer@example.com", password: "secret123456")

    assert_includes forum.reload.users, newcomer
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

  test "a forum counts as a sidebar room; a direct message does not" do
    assert rooms(:help_desk).sidebar_room?, "forums list in the sidebar with open and closed rooms"
    assert_not rooms(:david_and_jason).sidebar_room?, "directs stay out of the room sidebar"
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

  test "an opening post dots disconnected read members but not the author" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    forum.memberships.grant_to(users(:david))
    reader = forum.memberships.find_by!(user: users(:jason))
    reader.update_columns(connected_at: nil, connections: 0, marked_unread: false)
    author = forum.memberships.find_by!(user: users(:david))
    author.update_columns(connected_at: nil, connections: 0, marked_unread: false)

    create_forum_post(title: "Fresh question", forum: forum, author: users(:david))

    assert reader.reload.unread?, "a disconnected member should get the forum's sidebar dot"
    assert author.reload.read?, "the author never dots their own forum"
  end

  test "an opening post leaves connected members read" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    connected = forum.memberships.find_by!(user: users(:jason))
    connected.update_columns(connected_at: Time.current, connections: 1, marked_unread: false)

    create_forum_post(title: "Another question", forum: forum, author: users(:david))

    assert connected.reload.read?, "a member viewing live never gets the dot"
  end

  test "an opening post keeps an already-dotted member's forum dot" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    membership = forum.memberships.find_by!(user: users(:jason))
    membership.update_columns(connected_at: nil, connections: 0, marked_unread: true)

    create_forum_post(title: "Yet another question", forum: forum, author: users(:david))

    assert membership.reload.unread?, "an already-dotted forum stays dotted"
  end

  test "a reply to a post does not dot the forum" do
    forum = rooms(:help_desk)
    post = create_forum_post(title: "Existing discussion", forum: forum, author: users(:david))
    forum.memberships.grant_to(users(:jason))
    reader = forum.memberships.find_by!(user: users(:jason))
    reader.update_columns(connected_at: nil, connections: 0, marked_unread: false)

    post.messages.create!(body: "A reply", creator: users(:david), client_message_id: "forum_reply_no_dot")

    assert reader.reload.read?, "only a post's opening message dots the forum sidebar"
  end

  test "a new post writes no member rows and publishes one shared nudge" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    forum.memberships.grant_to(users(:kevin))
    others = forum.memberships.where.not(user_id: users(:david).id)
    others.each { |membership| catch_up membership }
    others.update_all(connected_at: nil, connections: 0)
    before = others.reload.map(&:attributes)
    ActionCable.server.pubsub.clear

    nudges = capture_broadcasts(RoomListChannel.broadcasting_for(Account.sole)) do
      create_forum_post(title: "Zero writes", forum: forum, author: users(:david))
    end

    assert_equal before, others.reload.map(&:attributes), "a post should not touch other members' rows"
    assert others.all?(&:unread?), "the dot still derives for every member who hasn't seen the post"
    assert_equal 1, nudges.count { |n| n["roomId"] == forum.id }, "one shared nudge for the forum"
    others.includes(:user).each do |membership|
      assert_empty ActionCable.server.pubsub.broadcasts(UserUnreadRoomsChannel.broadcasting_for(membership.user)),
        "no per-member dot push should fire"
    end
  end

  test "an author with an older unseen post keeps their dot when they post" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:david))
    author = forum.memberships.find_by!(user: users(:david))
    catch_up author
    author.update_columns(connected_at: nil, connections: 0)
    create_forum_post(title: "Someone else's question", forum: forum, author: users(:kevin))
    assert author.reload.unread?, "another member's post dots the author like anyone else"

    create_forum_post(title: "The author's own question", forum: forum, author: users(:david))

    assert author.reload.unread?, "posting must not clear the author's dot for posts they haven't seen"
  end

  test "deleting the only unseen post heals the forum dot" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:jason))
    reader = forum.memberships.find_by!(user: users(:jason))
    catch_up reader
    reader.update_columns(connected_at: nil, connections: 0)
    post = create_forum_post(title: "Soon deleted", forum: forum, author: users(:david))
    assert reader.reload.unread?, "the fresh post dots the reader"

    post.deactivate

    assert reader.reload.read?, "derived forum unread self-heals when the post disappears"
  end

  # --- Cascade & reactivation correctness --------------------------------

  test "restoring a forum restores posts that were active when it was deleted" do
    forum = rooms(:help_desk)
    post = create_forum_post

    perform_enqueued_jobs { forum.deactivate }
    assert post.reload.deactivated?

    perform_enqueued_jobs { forum.reactivate }
    assert post.reload.active?
  end

  test "restoring a forum does not resurrect a post that was individually deleted first" do
    forum = rooms(:help_desk)
    kept = create_forum_post(title: "Still open")
    removed = create_forum_post(title: "Deleted on its own")

    removed.deactivate
    assert removed.reload.deactivated?, "the post should be deleted on its own"

    perform_enqueued_jobs { forum.deactivate }
    perform_enqueued_jobs { forum.reactivate }

    assert kept.reload.active?, "a post active at forum-delete time should return"
    assert removed.reload.deactivated?, "an individually-deleted post must stay deleted"
  end

  test "a cascade-deactivated post carries the marker; a self-deleted post does not" do
    forum = rooms(:help_desk)
    self_deleted = create_forum_post(title: "self")
    cascaded = create_forum_post(title: "cascade")

    self_deleted.deactivate
    perform_enqueued_jobs { forum.deactivate }

    assert_not self_deleted.reload.cascade_deactivated?, "self-delete must not set the cascade marker"
    assert cascaded.reload.cascade_deactivated?, "cascade delete must set the marker"
  end

  test "the cascade marker is cleared when a post is restored" do
    forum = rooms(:help_desk)
    post = create_forum_post

    perform_enqueued_jobs { forum.deactivate }
    assert post.reload.cascade_deactivated?

    perform_enqueued_jobs { forum.reactivate }
    assert_not post.reload.cascade_deactivated?
  end

  # --- Async (de)activation: instant cutoff, background cascade --------------

  test "deleting a forum cuts access to its posts instantly, before the cascade job runs" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:david))
    post = create_forum_post
    assert post.viewable_by?(users(:david)), "a forum member can view a post beforehand"

    forum.deactivate # no perform_enqueued_jobs — the synchronous half must stand alone

    assert_not forum.reload.active?, "the forum row is deactivated synchronously"
    assert_not post.viewable_by?(users(:david)), "post access (derived from forum membership) is cut instantly"
  end

  test "deleting a forum enqueues the post-cascade job" do
    forum = rooms(:help_desk)
    create_forum_post

    assert_enqueued_with(job: ForumDeactivationJob) { forum.deactivate }
  end

  test "the post cascade runs in the background and re-running the job is a no-op" do
    forum = rooms(:help_desk)
    post = create_forum_post

    perform_enqueued_jobs { forum.deactivate }
    assert post.reload.deactivated?, "the background job soft-deletes the post"

    assert_nothing_raised { ForumDeactivationJob.perform_now(forum: forum) }
    assert post.reload.deactivated?, "re-running the job leaves the post deleted"
  end

  test "restoring a forum makes it visible instantly, before the post-restore job runs" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:david))
    create_forum_post
    perform_enqueued_jobs { forum.deactivate }
    assert_not forum.viewable_by?(users(:david))

    forum.reactivate # no perform_enqueued_jobs — the synchronous half must stand alone

    assert forum.reload.active?, "the forum row is reactivated synchronously"
    assert forum.viewable_by?(users(:david)), "forum membership is restored instantly — it reappears in the sidebar"
  end

  test "restoring a forum enqueues the post-restore job" do
    forum = rooms(:help_desk)
    create_forum_post
    perform_enqueued_jobs { forum.deactivate }

    assert_enqueued_with(job: ForumReactivationJob) { forum.reactivate }
  end

  # --- Concurrency + retry safety --------------------------------------------

  test "reactivating during a pending deactivation cancels the stale deletion" do
    forum = rooms(:help_desk)
    post = create_forum_post

    forum.deactivate # enqueues ForumDeactivationJob (not yet run)
    forum.reactivate # sync-flips the forum active again; enqueues ForumReactivationJob

    perform_enqueued_jobs # both run: the superseded deletion bails, the restore is a no-op

    assert forum.reload.active?
    assert post.reload.active?, "the post stays active — the superseded deletion job bailed"
  end

  test "deactivating during a pending reactivation cancels the stale restore" do
    forum = rooms(:help_desk)
    post = create_forum_post
    perform_enqueued_jobs { forum.deactivate }
    assert post.reload.deactivated?

    forum.reactivate # enqueues ForumReactivationJob (not yet run)
    forum.deactivate # sync-flips inactive again; enqueues ForumDeactivationJob

    perform_enqueued_jobs # the superseded restore bails, the deletion re-applies

    assert_not forum.reload.active?
    assert post.reload.deactivated?, "the post stays deleted — the superseded restore job bailed"
  end

  test "the deactivation job re-runs safely after a crash" do
    forum = rooms(:help_desk)
    post = create_forum_post
    forum.deactivate

    2.times { ForumDeactivationJob.perform_now(forum: forum) } # crash + retry re-runs from the start

    assert post.reload.deactivated?
  end

  test "hard-deleting a forum removes its posts" do
    forum = rooms(:help_desk)
    post = create_forum_post

    assert_nothing_raised { forum.destroy }

    assert_not Rooms::Post.exists?(post.id)
  end

  test "deleting a forum destroys notifications tied to its posts' messages" do
    forum = rooms(:help_desk)
    post = create_forum_post
    message = post.messages.first
    Notification.create!(user: users(:jason), message: message, actor: users(:david), activity_type: "thread_reply")

    assert_difference -> { Notification.where(message_id: message.id).count }, -1 do
      perform_enqueued_jobs { forum.deactivate }
    end
  end

  # --- Review-hardening -------------------------------------------------------

  test "an opening post that mentions a member routes a mention activity type" do
    forum = rooms(:help_desk)
    message = forum.messages.create!(body: "Ping", creator: users(:david))
    message.stubs(:mentionees).returns([ users(:jason) ])

    assert_includes forum.applicable_activity_types(message), :mention
  end

  # --- Sidebar unread from post activity --------------------------------------

  test "a new post marks the forum unread for other members but not the author" do
    forum = Rooms::Forum.create_for({ name: "Community", creator: users(:david) }, users: users(:david))

    Current.set(user: users(:david)) { forum.post!(title: "How do I reset?", body: "b") }

    kevin_membership = forum.memberships.find_by(user: users(:kevin))
    assert kevin_membership.unread?, "other members' forum membership is marked unread"
    assert_equal 0, kevin_membership.unread_notifications_count, "a plain new post is a dot, not a numbered mention"
    assert forum.memberships.find_by(user: users(:david)).read?, "the author isn't marked unread by their own post"
  end

  test "a plain reply does not mark the forum unread" do
    forum = Rooms::Forum.create_for({ name: "Community", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "b") }
    forum.memberships.each { |membership| catch_up membership }

    Current.set(user: users(:kevin)) { post.messages.create!(body: "<div>a reply</div>") }

    assert_empty forum.memberships.unread, "a plain reply leaves the forum read for every member"
  end

  test "a mention in a reply does not badge the forum — it surfaces in Activity only" do
    forum = Rooms::Forum.create_for({ name: "Community", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "b") }
    forum.memberships.each { |membership| catch_up membership }
    mention = %(<action-text-attachment sgid="#{users(:kevin).attachable_sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment>)

    Current.set(user: users(:david)) { post.messages.create!(body: "<div>#{mention} ping</div>") }

    kevin_membership = forum.memberships.find_by(user: users(:kevin))
    assert kevin_membership.read?, "a forum mention no longer marks the forum sidebar unread"
    assert_equal 0, kevin_membership.unread_notifications_count, "and no number badge on the forum — a forum mention is quiet, like a thread mention"
    assert_empty forum.memberships.unread, "a reply mention leaves the forum read for every member"
    assert Notification.exists?(user: users(:kevin), activity_type: "mention"),
      "the mention still reaches the member through Activity"
  end
end
