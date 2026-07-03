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

  test "create makes one opening message and one post-thread, persisting title and slug" do
    assert_difference [ -> { @forum.messages.count }, -> { Rooms::Thread.count } ], 1 do
      post rooms_forum_posts_url(@forum), params: { post: { title: "How do I reset?", body: "<div>Steps?</div>" } }
    end

    thread = Rooms::Thread.last
    assert_equal "How do I reset?", thread.title
    assert_equal "how-do-i-reset", thread.slug
    assert_redirected_to room_url(@forum)
  end

  test "a blank title is rejected and bounces back to the gallery with an alert" do
    assert_no_difference -> { Rooms::Thread.count } do
      post rooms_forum_posts_url(@forum), params: { post: { title: "", body: "<div>Body</div>" } }
    end

    assert_redirected_to room_url(@forum)
    assert flash[:alert].present?
  end

  test "every forum member can access a member's new post" do
    post rooms_forum_posts_url(@forum), params: { post: { title: "Shared", body: "<div>Body</div>" } }
    thread = Rooms::Thread.last

    # Kevin is a forum member but not the poster; he must still be a member of the post.
    assert_includes thread.users, users(:kevin)
  end

  test "creating a post does not mark the forum unread for other members" do
    kevin_membership = @forum.memberships.find_by(user: users(:kevin))
    assert kevin_membership.read?

    post rooms_forum_posts_url(@forum), params: { post: { title: "Quiet", body: "<div>Body</div>" } }

    assert kevin_membership.reload.read?, "opening a post should not mark the forum unread"
  end

  test "the new post appears in the forum gallery" do
    post rooms_forum_posts_url(@forum), params: { post: { title: "Latest", body: "<div>Body</div>" } }

    assert_includes @forum.threads.active, Rooms::Thread.last
  end

  test "a non-member cannot post to the forum" do
    sign_in :jz

    assert_no_difference -> { Rooms::Thread.count } do
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
