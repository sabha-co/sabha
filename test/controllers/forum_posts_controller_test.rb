require "test_helper"

class ForumPostsControllerTest < ActionDispatch::IntegrationTest
  def create_post(members: [ users(:david) ], author: users(:david))
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: members)
    Current.set(user: author) { @forum.post!(title: "How do I reset my password?", body: "<div>Steps</div>") }
  end

  test "a member sees the standalone post page with no redirect" do
    sign_in :david
    post = create_post

    get forum_post_url(post.slug)

    assert_response :success
    assert_select ".forum-post-header__title", text: "How do I reset my password?"
    assert_select "#thread-message-area"
  end

  test "the opening post renders as a hero with an OP badge, distinct from replies" do
    sign_in :david
    post = create_post(members: [ users(:david), users(:kevin) ])
    Current.set(user: users(:kevin)) { post.messages.create!(body: "<div>A reply</div>") }

    get forum_post_url(post.slug)

    assert_response :success
    assert_select ".forum-post-header__glyph"
    # The opening message lives in the forum and gets the roomier "question" treatment.
    assert_select ".message--forum-opening"
    # The original poster (david) is badged on the opening message; kevin's reply is not.
    assert_select ".message--forum-opening .message__op-badge", text: "OP"
    assert_select ".message__op-badge", count: 1
  end

  test "a logged-in non-member sees the join CTA, not the post content or a root bounce" do
    post = create_post(members: [ users(:david) ])
    sign_in :kevin

    get forum_post_url(post.slug)

    assert_response :forbidden
    assert_select ".forum-post-gated"
    assert_select "form[action=?]", room_membership_path(@forum)
    # The message list must never render for a non-member.
    assert_select "#thread-message-area", count: 0
    assert_select ".message", count: 0
  end

  test "a logged-out visitor is sent to auth and returned to the post URL" do
    post = create_post

    get forum_post_url(post.slug)

    assert_response :redirect
    assert_includes session[:return_to_after_authenticating].to_s, "/f/#{post.slug}"
  end

  test "a deactivated post renders 404, not the message list" do
    sign_in :david
    post = create_post
    post.deactivate

    get forum_post_url(post.slug)

    assert_response :not_found
    assert_select ".forum-post-missing"
    assert_select "#thread-message-area", count: 0
  end

  test "an unknown slug renders 404" do
    sign_in :david

    get forum_post_url("does-not-exist")

    assert_response :not_found
  end

  test "deleting the opening message removes the post from its canonical page too" do
    sign_in :david
    post = create_post
    post.parent_message.deactivate

    get forum_post_url(post.slug)

    assert_response :not_found
  end
end
