require "test_helper"

class Rooms::Posts::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
    @post = Current.set(user: users(:david)) { @forum.post!(title: "How do I reset?", body: "<div>b</div>") }
  end

  test "a forum member Follows a post by creating a membership" do
    sign_in :kevin
    assert_not Membership.exists?(room_id: @post.id, user_id: users(:kevin).id)

    post rooms_post_membership_url(@post)

    membership = Membership.find_by(room_id: @post.id, user_id: users(:kevin).id)
    assert membership.present?, "Follow creates the membership"
    assert_equal "everything", membership.involvement
  end

  test "Unfollow removes the membership" do
    @post.follow!(users(:kevin))
    sign_in :kevin

    delete rooms_post_membership_url(@post)

    assert_not Membership.exists?(room_id: @post.id, user_id: users(:kevin).id)
  end

  test "a non-forum-member cannot Follow a post" do
    sign_in :jz

    post rooms_post_membership_url(@post)

    assert_response :forbidden
    assert_not Membership.exists?(room_id: @post.id, user_id: users(:jz).id)
  end

  test "Following a nonexistent post returns 404, not 403" do
    sign_in :kevin

    post rooms_post_membership_url(999_999)

    assert_response :not_found
  end
end
