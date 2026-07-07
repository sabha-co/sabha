require "test_helper"

class Rooms::ThreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  # ===================
  # Create action tests
  # ===================

  test "create creates thread and redirects to show" do
    parent_message = @room.messages.create!(
      body: "Parent message for thread",
      creator: @jason,
      client_message_id: "thread_new_1"
    )

    assert_difference -> { Rooms::Thread.count }, 1 do
      post rooms_threads_url, params: { parent_message_id: parent_message.id }
    end

    thread = Rooms::Thread.last
    assert_equal parent_message.id, thread.parent_message_id
    assert_redirected_to rooms_thread_url(thread)
  end

  test "create redirects to existing thread if one exists" do
    parent_message = @room.messages.create!(
      body: "Parent with existing thread",
      creator: @jason,
      client_message_id: "thread_existing_1"
    )

    existing_thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    existing_thread.memberships.grant_to(@david)

    assert_no_difference -> { Rooms::Thread.count } do
      post rooms_threads_url, params: { parent_message_id: parent_message.id }
    end

    assert_redirected_to rooms_thread_url(existing_thread)
  end

  test "create grants a membership to the creator and the parent-message author, not every parent room member" do
    kevin = users(:kevin)
    @room.memberships.grant_to(kevin) # a third parent-room member, uninvolved
    parent_message = @room.messages.create!(
      body: "Parent message",
      creator: @jason,
      client_message_id: "thread_membership_1"
    )

    post rooms_threads_url, params: { parent_message_id: parent_message.id }
    assert_response :redirect

    thread = Rooms::Thread.last
    assert_equal [ @david.id, @jason.id ].sort, thread.memberships.pluck(:user_id).sort,
      "the thread creator and the parent-message author each get a row — a thread never fans out to every member"
    assert_equal "everything", thread.memberships.find_by(user: @jason).involvement,
      "the parent-message author auto-follows so replies to their message notify them"
    assert_not thread.memberships.exists?(user: kevin), "an uninvolved parent member gets no row"
    assert thread.viewable_by?(kevin), "…but still views via derived access"
  end

  test "create does not subscribe a member who merely opens an existing thread" do
    kevin = users(:kevin)
    @room.memberships.grant_to(kevin)
    parent_message = @room.messages.create!(
      body: "Parent for lurk test", creator: @jason, client_message_id: "lurk_open_1"
    )
    thread = Rooms::Thread.create_for(
      { parent_message_id: parent_message.id, creator: @david }, users: [ @david, @jason ]
    )

    sign_in :kevin
    post rooms_threads_url, params: { parent_message_id: parent_message.id }

    assert_not thread.memberships.exists?(user: kevin),
      "opening a thread doesn't subscribe you — you follow by replying or via the Follow control"
    assert thread.viewable_by?(kevin), "…but you can still view it via derived access"
  end

  test "create requires parent message to be reachable by user" do
    # Create a message in a room david is not a member of
    closed_room = Rooms::Closed.create!(name: "Secret Room", creator: @jason)
    closed_room.memberships.grant_to(@jason)
    parent_message = closed_room.messages.create!(
      body: "Secret message",
      creator: @jason,
      client_message_id: "unreachable_1"
    )

    post rooms_threads_url, params: { parent_message_id: parent_message.id }
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  test "create does not allow threads on direct messages" do
    dm_room = rooms(:david_and_jason)
    dm_message = dm_room.messages.create!(
      body: "DM message",
      creator: @jason,
      client_message_id: "dm_thread_1"
    )

    post rooms_threads_url, params: { parent_message_id: dm_message.id }
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  test "create does not allow nested threads" do
    parent_message = @room.messages.create!(
      body: "Parent message",
      creator: @jason,
      client_message_id: "nested_thread_parent_1"
    )
    thread = Rooms::Thread.create_for(
      { parent_message_id: parent_message.id, creator: @jason },
      users: [ @david, @jason ]
    )
    thread_message = thread.messages.create!(
      body: "Thread reply",
      creator: @jason,
      client_message_id: "nested_thread_msg_1"
    )

    assert_no_difference -> { Rooms::Thread.count } do
      post rooms_threads_url, params: { parent_message_id: thread_message.id }
    end

    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  test "create redirects with alert for non-existent message" do
    post rooms_threads_url, params: { parent_message_id: 999999 }
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  # Note: The unique constraint prevents creating a new thread when an inactive one exists
  # This is by design - threads are unique per parent message

  # ===================
  # Show action tests
  # ===================

  test "show renders thread panel without layout" do
    parent_message = @room.messages.create!(
      body: "Parent for layout test",
      creator: @jason,
      client_message_id: "layout_thread_1"
    )

    thread = Rooms::Thread.create_for({ parent_message_id: parent_message.id, creator: @jason }, users: [ @david, @jason ])

    get rooms_thread_url(thread)
    assert_response :success
    assert_select "turbo-frame#thread_panel_frame"
  end

  test "show requires access to the parent room" do
    parent_message = @room.messages.create!(
      body: "Parent for access test",
      creator: @jason,
      client_message_id: "access_thread_1"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)

    # kevin is not a member of the parent room, so thread access is denied —
    # access derives from the parent room, not from a per-thread membership.
    sign_in :kevin
    get rooms_thread_url(thread)
    assert_redirected_to root_url
  end

  # ===================
  # Edit action tests
  # ===================

  test "edit loads visible users" do
    parent_message = @room.messages.create!(
      body: "Parent for users test",
      creator: @jason,
      client_message_id: "users_thread_1"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    get edit_rooms_thread_url(thread)
    assert_response :success
    assert_match @david.name, response.body
    assert_match @jason.name, response.body
  end

  # ===================
  # Update action tests
  # ===================

  test "update changes thread name" do
    parent_message = @room.messages.create!(
      body: "Parent for update test",
      creator: @jason,
      client_message_id: "update_thread_1"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @david, name: "Old Name")
    thread.memberships.grant_to(@david)

    patch rooms_thread_url(thread), params: { room: { name: "New Thread Name" } }
    assert_redirected_to room_at_message_url(parent_message.room, parent_message)

    thread.reload
    assert_equal "New Thread Name", thread.name
  end

  test "update requires appropriate permissions" do
    sign_in :jz
    @jz = users(:jz)
    @room.memberships.grant_to(@jz) # a parent-room member, so jz can view the thread…

    parent_message = @room.messages.create!(
      body: "Parent for update permission test",
      creator: @jason,
      client_message_id: "update_perm_thread_1"
    )

    thread = Rooms::Thread.create_for({ parent_message_id: parent_message.id, creator: @david }, users: [ @jz ])

    # …but jz is neither the creator nor an admin, so renaming is forbidden.
    patch rooms_thread_url(thread), params: { room: { name: "Hijacked Name" } }
    assert_response :forbidden

    thread.reload
    assert_not_equal "Hijacked Name", thread.name
  end

  # ===================
  # Destroy action tests
  # ===================

  # Note: Thread destruction is tested via system tests due to complex permission/membership setup
  # The destroy action requires:
  # 1. User to have active membership in the thread (for set_room to find it)
  # 2. User to pass can_administer? check (creator or administrator)
  # Both conditions are checked before the action runs

  test "destroy requires appropriate permissions" do
    sign_in :jz
    @jz = users(:jz)
    @room.memberships.grant_to(@jz) # a parent-room member, so jz can view the thread…

    parent_message = @room.messages.create!(
      body: "Parent for permission test",
      creator: @jason,
      client_message_id: "permission_thread_1"
    )

    thread = Rooms::Thread.create_for({ parent_message_id: parent_message.id, creator: @david }, users: [ @jz ])

    # …but jz is neither the creator nor an admin, so deleting is forbidden.
    delete rooms_thread_url(thread)
    assert_response :forbidden

    thread.reload
    assert thread.active?, "Thread should still be active"
  end

  test "cannot start a chat thread off a forum's opening post message" do
    sign_in :david
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    opening = post.messages.first

    assert_no_difference -> { Rooms::Thread.count } do
      post rooms_threads_url, params: { parent_message_id: opening.id }
    end
    assert_redirected_to root_url
  end
end
