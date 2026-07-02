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
end
