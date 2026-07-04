require "test_helper"

# Characterization net for chat-thread access, reply notifications, inbox
# surfacing, and removal-cleanup. These pin the CURRENT observable behavior so it
# survives Part A's refactor from fanned thread memberships to parent-derived
# access. Every test here MUST stay green through A2–A5 — the mechanism changes
# underneath (fanned rows → derived access), the behavior must not.
#
# Roles:
#   david (@creator)  — opens the thread; an "everything" follower
#   jason (@member)   — a parent-room member; passive unless a test says otherwise
#   kevin (@passive)  — granted to the parent room, fanned in, never posts
#   jz    (@outsider) — never a member of the parent room
class ThreadAccessCharacterizationTest < ActionDispatch::IntegrationTest
  setup do
    @parent = rooms(:pets)            # Open room; fixtures give it david (creator) + jason
    @creator = users(:david)
    @member = users(:jason)
    @passive = users(:kevin)
    @outsider = users(:jz)

    @parent.memberships.grant_to(@passive)   # kevin joins the parent room
    @parent_message = @parent.messages.create!(body: "Let's discuss", creator: @creator)
    @thread = Rooms::Thread.create_for(
      { parent_message_id: @parent_message.id, creator: @creator },
      users: @parent.users               # production fan-out path: david, jason, kevin
    )
  end

  # ---- Access -------------------------------------------------------------

  test "a parent-room member can open a thread they never posted in" do
    sign_in :jason
    get rooms_thread_url(@thread)
    assert_response :success
  end

  test "a non-member of the parent room cannot open the thread" do
    sign_in :jz
    get rooms_thread_url(@thread)
    assert_redirected_to root_url
  end

  test "removing a member from the parent room removes their thread access" do
    # Use a Closed room so removal is the semantically real path, and let the
    # member engage first so a thread-follow row lingers after removal — that
    # exercises the stale-row defense (T4) once fan-out cascade is gone.
    closed = Rooms::Closed.create!(name: "War Room", creator: @creator)
    closed.memberships.grant_to([ @creator, @member ])
    parent = closed.messages.create!(body: "hi", creator: @creator)
    thread = Rooms::Thread.create_for(
      { parent_message_id: parent.id, creator: @creator }, users: closed.users
    )
    Current.set(user: @member) { thread.messages.create!(body: "count me in", creator: @member) }

    sign_in :jason
    get rooms_thread_url(thread)
    assert_response :success, "member has thread access before removal"

    closed.remove_member!(@member, actor: @creator)

    get rooms_thread_url(thread)
    assert_redirected_to root_url, "removal from the parent room revokes thread access"
  end

  # ---- Reply notifications -------------------------------------------------

  test "a reply notifies active thread followers, not passive members or non-members" do
    reply = nil
    perform_enqueued_jobs do
      reply = Current.set(user: @member) do
        @thread.messages.create!(body: "my reply", creator: @member)
      end
    end

    assert Notification.exists?(user: @creator, message: reply, activity_type: "thread_reply"),
      "the everything-follower is notified"
    assert_not Notification.exists?(user: @passive, message: reply, activity_type: "thread_reply"),
      "a passive (invisible) parent member is not notified"
    assert_not Notification.exists?(user: @outsider, message: reply, activity_type: "thread_reply"),
      "a non-member is never a target"
  end

  test "a parent-room member can be @mentioned in a thread without a thread membership" do
    # A creator-only thread (no fan-out): jason is a parent member but not a
    # thread member, yet an @mention must still resolve and notify him.
    parent_message = @parent.messages.create!(body: "topic", creator: @creator)
    thread = Rooms::Thread.find_or_create_for(parent_message, creator: @creator)
    assert_not Membership.exists?(room_id: thread.id, user_id: @member.id),
      "precondition: the mentionee is not a thread member"

    reply = nil
    perform_enqueued_jobs do
      reply = Current.set(user: @creator) do
        thread.messages.create!(
          body: "<div>hey #{mention_attachment_for(:jason)}</div>",
          creator: @creator,
          client_message_id: "thread-mention-1"
        )
      end
    end

    assert_includes reply.mentionee_ids, @member.id, "a parent member resolves via the parent-room roster"
    assert Notification.exists?(user: @member, message: reply, activity_type: "mention")
  end

  # ---- Inbox threads -------------------------------------------------------

  test "inbox threads surfaces a followed thread and hides it from a non-member" do
    Current.set(user: @creator) { @thread.messages.create!(body: "kick off", creator: @creator) }

    assert_includes Inbox::ThreadsQuery.new(@creator).call.map(&:id), @parent_message.id,
      "the creator follows the thread and sees it in their inbox"
    assert_not_includes Inbox::ThreadsQuery.new(@outsider).call.map(&:id), @parent_message.id,
      "a non-member does not see the thread in their inbox"
  end

  test "an everything-in-parent member sees the thread in their inbox without a thread membership" do
    @parent.memberships.find_by(user: @member).update!(involvement: :everything)

    parent_message = @parent.messages.create!(body: "another topic", creator: @creator)
    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @creator)
    thread.messages.create!(body: "reply", creator: @creator)

    assert_not Membership.exists?(room_id: thread.id, user_id: @member.id),
      "no thread membership — access derives from everything-in-parent"
    assert_includes Inbox::ThreadsQuery.new(@member).call.map(&:id), parent_message.id
  end

  # ---- Unread badges (threads drive none) ----------------------------------

  test "a thread reply drives no unread badge for a passive parent member" do
    before = @member.memberships.unread.count

    Current.set(user: @creator) { @thread.messages.create!(body: "ping", creator: @creator) }

    assert_equal before, @member.reload.memberships.unread.count,
      "thread activity must not raise an unread badge for a passive parent member"
  end
end
