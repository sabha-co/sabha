require "test_helper"

class Rooms::Forums::PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
    @question = @forum.tags.create!(name: "Question")
  end

  test "new renders the compose form with the forum's tags" do
    get new_rooms_forum_post_url(@forum)

    assert_response :success
    assert_select "form[action=?]", rooms_forum_posts_path(@forum)
    assert_select "input[name='post[title]']"
    assert_select "input[name='post[tag_ids][]'][value=?]", @question.id.to_s
  end

  test "create makes one opening message and one post-thread, persisting title, slug, and tags" do
    assert_difference [ -> { @forum.messages.count }, -> { Rooms::Thread.count } ], 1 do
      post rooms_forum_posts_url(@forum), params: { post: { title: "How do I reset?", body: "<div>Steps?</div>", tag_ids: [ @question.id ] } }
    end

    thread = Rooms::Thread.last
    assert_equal "How do I reset?", thread.title
    assert_equal "how-do-i-reset", thread.slug
    assert_equal [ @question ], thread.tags.to_a
    assert_redirected_to rooms_forum_url(@forum)
  end

  test "a post can be created with no tags" do
    assert_difference -> { Rooms::Thread.count }, 1 do
      post rooms_forum_posts_url(@forum), params: { post: { title: "No tags here", body: "<div>Body</div>" } }
    end

    assert_empty Rooms::Thread.last.tags
  end

  test "a blank title is rejected" do
    assert_no_difference -> { Rooms::Thread.count } do
      post rooms_forum_posts_url(@forum), params: { post: { title: "", body: "<div>Body</div>" } }
    end

    assert_response :unprocessable_entity
  end

  test "every forum member can access a member's new post" do
    post rooms_forum_posts_url(@forum), params: { post: { title: "Shared", body: "<div>Body</div>" } }
    thread = Rooms::Thread.last

    # Kevin is a forum member but not the poster; he must still be a member of the post.
    assert_includes thread.users, users(:kevin)
  end

  test "a tag from another forum cannot be attached to this forum's post" do
    other_forum = Rooms::Forum.create_for({ name: "Other", creator: users(:david) }, users: users(:david))
    foreign_tag = other_forum.tags.create!(name: "Foreign")

    post rooms_forum_posts_url(@forum), params: { post: { title: "Crafted", body: "<div>Body</div>", tag_ids: [ @question.id, foreign_tag.id ] } }
    thread = Rooms::Thread.last

    assert_equal [ @question ], thread.tags.to_a
    assert_not_includes thread.tags, foreign_tag
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

  # --- Editing a post's title and tags after creation (R8) --------------------

  test "the original poster can edit the post's title and tags after creation" do
    setup_tag = @forum.tags.create!(name: "Setup")
    post = Current.set(user: users(:kevin)) do
      @forum.post!(title: "Original", body: "<div>b</div>", tag_ids: [ @question.id ])
    end
    sign_in :kevin

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Edited title", tag_ids: [ setup_tag.id ] } }

    post.reload
    assert_equal "Edited title", post.title
    assert_equal [ setup_tag ], post.tags.to_a
    assert_redirected_to rooms_forum_url(@forum)
  end

  test "editing a post's title does not change its slug" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Keep the slug", body: "<div>b</div>") }
    original_slug = post.slug
    sign_in :kevin

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "A brand new title" } }

    assert_equal original_slug, post.reload.slug
  end

  test "editing cannot attach another forum's tag" do
    post = Current.set(user: users(:kevin)) { @forum.post!(title: "Scoped", body: "<div>b</div>") }
    foreign = Rooms::Forum.create_for({ name: "Other", creator: users(:david) }, users: users(:david)).tags.create!(name: "Foreign")
    sign_in :kevin

    patch rooms_forum_post_url(@forum, post), params: { post: { title: "Scoped", tag_ids: [ @question.id, foreign.id ] } }

    assert_equal [ @question ], post.reload.tags.to_a
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
