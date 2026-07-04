require "test_helper"

class Rooms::PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
    @post = Current.set(user: users(:david)) { @forum.post!(title: "How do I reset?", body: "<div>b</div>") }
  end

  test "a forum member can open the post panel without holding a post membership" do
    sign_in :kevin # forum member, not the author, not a follower
    assert_not Membership.exists?(room_id: @post.id, user_id: users(:kevin).id)

    get rooms_post_url(@post)

    assert_response :success
    assert_select "#thread_panel_frame"
    assert_select ".forum-post-header__title", text: "How do I reset?"
  end

  test "a non-forum-member is forbidden from the post panel" do
    sign_in :jz # not a forum member

    get rooms_post_url(@post)

    assert_response :forbidden
  end

  test "an unknown post id renders 404" do
    sign_in :david

    get rooms_post_url(id: 0)

    assert_response :not_found
  end
end
