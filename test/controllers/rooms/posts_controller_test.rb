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

  test "the opening message renders as a hero, badged OP, divided from replies by a live count" do
    Current.set(user: users(:kevin)) { @post.messages.create!(body: "<div>A reply</div>") }
    sign_in :david

    get rooms_post_url(@post)

    assert_response :success
    # The opening message carries the post body and gets the roomier treatment.
    assert_select ".message--forum-opening"
    # The author (david) is badged OP on the opening message; kevin's reply is not.
    assert_select ".message--forum-opening .message__op-badge", text: "OP"
    assert_select ".message__op-badge", count: 1
    # A "N replies" divider separates the question from the discussion; its count
    # span carries the id a new reply broadcasts to (Message::Threadable).
    count_id = "#{ActionView::RecordIdentifier.dom_id(@post, :replies_separator)}_count"
    assert_select ".message--forum-opening .message__replies-separator ##{count_id}", text: "1 reply"
    assert_select ".message:not(.message--forum-opening) .message__replies-separator", count: 0
  end

  test "a non-forum-member is forbidden from the post panel" do
    @forum.remove_member!(users(:jz), actor: users(:david)) # auto-joined, then removed
    sign_in :jz # not a forum member

    get rooms_post_url(@post)

    assert_response :forbidden
  end

  test "an unknown post id renders 404" do
    sign_in :david

    get rooms_post_url(id: 0)

    assert_response :not_found
  end

  test "a member removed from the forum loses read and reply access to a post they engaged with" do
    # kevin replies, gaining an active per-post membership
    Current.set(user: users(:kevin)) { @post.messages.create!(body: "<div>reply</div>", creator: users(:kevin)) }
    assert Membership.exists?(room_id: @post.id, user_id: users(:kevin).id)

    @forum.remove_member!(users(:kevin), actor: users(:david))
    sign_in :kevin

    # Access derives from forum membership, so the stale post membership grants nothing.
    get rooms_post_url(@post)
    assert_response :forbidden

    assert_no_difference -> { @post.messages.count } do
      post room_messages_url(@post), params: { message: { body: "<div>sneaky</div>" } }
    end
  end
end
