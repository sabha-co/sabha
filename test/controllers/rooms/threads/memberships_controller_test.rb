require "test_helper"

class Rooms::Threads::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @kevin = users(:kevin)
    @room = rooms(:pets)
    @parent_message = @room.messages.create!(
      body: "Parent for follow tests", creator: @jason, client_message_id: "tm_setup_1"
    )
    @thread = Rooms::Thread.create_for(
      { parent_message_id: @parent_message.id, creator: @david }, users: [ @david, @jason ]
    )
  end

  test "a parent-room member Follows a thread by creating a membership at everything" do
    @room.memberships.grant_to(@kevin)
    sign_in :kevin
    assert_not Membership.exists?(room_id: @thread.id, user_id: @kevin.id)

    post rooms_thread_membership_url(@thread)

    membership = Membership.find_by(room_id: @thread.id, user_id: @kevin.id)
    assert membership.present?, "Follow creates the membership"
    assert_equal "everything", membership.involvement, "a follower lands at everything, like a post follower"
  end

  test "Following via a turbo frame flips the button to Unfollow" do
    @room.memberships.grant_to(@kevin)
    sign_in :kevin

    post rooms_thread_membership_url(@thread), headers: { "Turbo-Frame" => "follow" }

    assert_response :success
    assert_select "turbo-stream[action='replace'][target=?]", ActionView::RecordIdentifier.dom_id(@thread, :follow)
    assert_select "turbo-frame button", text: /Unfollow/
  end

  test "Unfollow removes the membership" do
    @thread.follow!(@kevin)
    @room.memberships.grant_to(@kevin)
    sign_in :kevin

    delete rooms_thread_membership_url(@thread)

    assert_not Membership.exists?(room_id: @thread.id, user_id: @kevin.id)
  end

  test "Unfollow via a turbo frame flips the button back to Follow" do
    @thread.follow!(@kevin)
    @room.memberships.grant_to(@kevin)
    sign_in :kevin

    delete rooms_thread_membership_url(@thread), headers: { "Turbo-Frame" => "follow" }

    assert_response :success
    assert_select "turbo-frame button", text: /Follow/
  end

  test "a non-parent-room member cannot Follow a thread" do
    sign_in :kevin # kevin is not a member of the parent room

    post rooms_thread_membership_url(@thread)

    assert_response :forbidden
    assert_not Membership.exists?(room_id: @thread.id, user_id: @kevin.id)
  end

  test "Following a nonexistent thread returns 404, not 403" do
    sign_in :david

    post rooms_thread_membership_url(999_999)

    assert_response :not_found
  end

  test "the auto-subscribed parent-message author can Unfollow, and it persists across reopening" do
    sign_in :jason
    assert @thread.followed_by?(@jason), "the parent-message author is auto-subscribed on thread creation"

    delete rooms_thread_membership_url(@thread)
    assert_not @thread.followed_by?(@jason), "Unfollow drops the author's subscription"

    # Reopening the thread must not silently re-subscribe them.
    post rooms_threads_url, params: { parent_message_id: @parent_message.id }
    assert_not @thread.reload.followed_by?(@jason), "Unfollow persists — reopening the thread doesn't re-subscribe"
  end
end
