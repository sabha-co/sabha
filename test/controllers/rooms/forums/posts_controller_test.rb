require "test_helper"

class Rooms::Forums::PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
  end

  test "the gallery carries the inline compose form" do
    get room_url(@forum)

    assert_response :success
    assert_select "form[action=?]", rooms_forum_posts_path(@forum)
    assert_select "input[name='post[title]']"
  end

  test "create makes one post with its opening message, persisting title and slug" do
    assert_difference -> { Rooms::Post.count }, 1 do
      post rooms_forum_posts_url(@forum), params: { post: { title: "How do I reset?", body: "<div>Steps?</div>" } }
    end

    created = Rooms::Post.last
    assert_equal "How do I reset?", created.title
    assert_equal "how-do-i-reset", created.slug
    assert_equal 1, created.messages.count, "the body becomes message #1"
    assert_redirected_to room_url(@forum)
  end

  test "a blank title is rejected and bounces back to the gallery with an alert" do
    assert_no_difference -> { Rooms::Post.count } do
      post rooms_forum_posts_url(@forum), params: { post: { title: "", body: "<div>Body</div>" } }
    end

    assert_redirected_to room_url(@forum)
    assert flash[:alert].present?
  end

  test "a forum member can view a member's new post without holding a post membership" do
    post rooms_forum_posts_url(@forum), params: { post: { title: "Shared", body: "<div>Body</div>" } }
    created = Rooms::Post.last

    # Kevin is a forum member but not the poster: no per-post membership row,
    # yet access derives from forum membership.
    assert_not_includes created.users, users(:kevin)
    assert created.viewable_by?(users(:kevin))
  end

  test "creating a post does not mark the forum unread for other members" do
    kevin_membership = @forum.memberships.find_by(user: users(:kevin))
    assert kevin_membership.read?

    post rooms_forum_posts_url(@forum), params: { post: { title: "Quiet", body: "<div>Body</div>" } }

    assert kevin_membership.reload.read?, "opening a post should not mark the forum unread"
  end

  test "the new post appears in the forum gallery" do
    post rooms_forum_posts_url(@forum), params: { post: { title: "Latest", body: "<div>Body</div>" } }

    assert_includes @forum.posts, Rooms::Post.last
  end

  test "a non-member cannot post to the forum" do
    sign_in :jz

    assert_no_difference -> { Rooms::Post.count } do
      post rooms_forum_posts_url(@forum), params: { post: { title: "Intruder", body: "<div>Body</div>" } }
    end

    assert_redirected_to root_url
  end

  # --- Editing a post's title after creation (R8) -----------------------------

  test "the original poster can edit the post's title after creation" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Original", body: "<div>b</div>") }
    sign_in :kevin

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Edited title" } }

    assert_equal "Edited title", post.reload.title
    assert_redirected_to forum_post_url(post.slug)
  end

  test "editing a post's title does not change its slug" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Keep the slug", body: "<div>b</div>") }
    original_slug = post.slug
    sign_in :kevin

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "A brand new title" } }

    assert_equal original_slug, post.reload.slug
  end

  test "a deleted post cannot be edited through the nested route" do
    post = Current.set(user: users(:david)) { @forum.post!(title: "Doomed", body: "<div>b</div>") }
    post.deactivate

    get edit_rooms_forum_post_url(@forum, post)
    assert_redirected_to room_url(@forum)

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Zombie" } }
    assert_redirected_to room_url(@forum)
    assert_equal "Doomed", post.reload.name
  end

  test "a non-OP non-admin member cannot edit a post" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Mine", body: "<div>b</div>") }
    @forum.memberships.grant_to(users(:jz))
    sign_in :jz

    get edit_rooms_forum_post_url(@forum, post)
    assert_response :forbidden

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Hijacked" } }
    assert_response :forbidden
    assert_equal "Mine", post.reload.title
  end

  test "an admin can edit any post" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Mine", body: "<div>b</div>") }
    sign_in :david  # admin, not OP

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Admin edited" } }

    assert_equal "Admin edited", post.reload.title
  end

  # --- Deleting a post (D4) ---------------------------------------------------

  test "the author can delete a post, deactivating it" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Remove me", body: "<div>b</div>") }
    sign_in :kevin

    delete rooms_forum_post_url(@forum, post)

    assert post.reload.deactivated?
    assert_redirected_to room_url(@forum)
  end

  test "a non-author non-admin member cannot delete a post" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Mine", body: "<div>b</div>") }
    @forum.memberships.grant_to(users(:jz))
    sign_in :jz

    delete rooms_forum_post_url(@forum, post)

    assert_response :forbidden
    assert post.reload.active?
  end

  test "the opening message of a post cannot be deleted on its own" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Keep body", body: "<div>b</div>") }
    opening = post.messages.first
    sign_in :kevin

    delete room_message_url(post, opening)

    assert_response :forbidden
    assert opening.reload.active?, "the post body must survive; delete the post instead"
  end

  test "editing a post broadcasts a card and header refresh to the live surfaces" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Original", body: "<div>b</div>") }
    sign_in :kevin

    assert_turbo_stream_broadcasts [ @forum, :posts ], count: 1 do
      assert_turbo_stream_broadcasts [ post, :messages ], count: 1 do
        patch rooms_forum_post_url(@forum, post), params: { post: { title: "Edited title" } }
      end
    end
  end
end
