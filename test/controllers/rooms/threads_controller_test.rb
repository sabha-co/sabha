require "test_helper"

class Rooms::ThreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  # ===================
  # New action tests
  # ===================

  test "new creates thread and redirects to it" do
    parent_message = @room.messages.create!(
      body: "Parent message for thread",
      creator: @jason,
      client_message_id: "thread_new_1"
    )

    assert_difference -> { Rooms::Thread.count }, 1 do
      get new_rooms_thread_url(parent_message_id: parent_message.id)
    end

    thread = Rooms::Thread.last
    assert_redirected_to room_url(thread)
    assert_equal parent_message.id, thread.parent_message_id
  end

  test "new redirects to existing thread if one exists" do
    parent_message = @room.messages.create!(
      body: "Parent with existing thread",
      creator: @jason,
      client_message_id: "thread_existing_1"
    )

    existing_thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)

    assert_no_difference -> { Rooms::Thread.count } do
      get new_rooms_thread_url(parent_message_id: parent_message.id)
    end

    assert_redirected_to room_url(existing_thread)
  end

  test "new grants membership to all parent room users" do
    parent_message = @room.messages.create!(
      body: "Parent message",
      creator: @jason,
      client_message_id: "thread_membership_1"
    )

    get new_rooms_thread_url(parent_message_id: parent_message.id)

    thread = Rooms::Thread.last
    @room.users.each do |user|
      assert thread.memberships.exists?(user: user), "Thread should have membership for #{user.name}"
    end
  end

  test "new requires parent message to be reachable by user" do
    # Create a message in a room david is not a member of
    closed_room = Rooms::Closed.create!(name: "Secret Room", creator: @jason)
    closed_room.memberships.grant_to(@jason)
    parent_message = closed_room.messages.create!(
      body: "Secret message",
      creator: @jason,
      client_message_id: "unreachable_1"
    )

    get new_rooms_thread_url(parent_message_id: parent_message.id)
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  test "new does not allow threads on direct messages" do
    dm_room = rooms(:david_and_jason)
    dm_message = dm_room.messages.create!(
      body: "DM message",
      creator: @jason,
      client_message_id: "dm_thread_1"
    )

    get new_rooms_thread_url(parent_message_id: dm_message.id)
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  test "new redirects with alert for non-existent message" do
    get new_rooms_thread_url(parent_message_id: 999999)
    assert_redirected_to root_url
    assert_equal "Message not found or inaccessible", flash[:alert]
  end

  # Note: The unique constraint prevents creating a new thread when an inactive one exists
  # This is by design - threads are unique per parent message

  # ===================
  # Edit action tests
  # ===================

  test "edit shows thread settings" do
    parent_message = @room.messages.create!(
      body: "Parent for edit test",
      creator: @jason,
      client_message_id: "edit_thread_1"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @david)
    thread.memberships.grant_to(@david)

    get edit_rooms_thread_url(thread)
    assert_response :success
  end

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
    assert_redirected_to room_url(thread)

    thread.reload
    assert_equal "New Thread Name", thread.name
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

    parent_message = @room.messages.create!(
      body: "Parent for permission test",
      creator: @jason,
      client_message_id: "permission_thread_1"
    )

    thread = Rooms::Thread.create_for({ parent_message_id: parent_message.id, creator: @david }, users: [ @jz ])

    # jz is not creator or admin, should be forbidden
    delete rooms_thread_url(thread)
    assert_response :forbidden

    thread.reload
    assert thread.active?, "Thread should still be active"
  end
end
