require "test_helper"

class Rooms::Forums::Posts::SolutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    # david = admin, kevin = OP (poster), jz = plain member.
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) },
                                     users: [ users(:david), users(:kevin), users(:jz) ])
    @post = Current.set(user: users(:kevin)) { @forum.post!(title: "How do I reset?", body: "<div>b</div>") }
  end

  test "the original poster can mark a post Solved (AE1)" do
    sign_in :kevin
    assert_not @post.solved?

    post rooms_forum_post_solution_url(@forum, @post)

    assert @post.reload.solved?
  end

  test "an admin can mark and reopen a post" do
    sign_in :david

    post rooms_forum_post_solution_url(@forum, @post)
    assert @post.reload.solved?

    delete rooms_forum_post_solution_url(@forum, @post)
    assert_not @post.reload.solved?
  end

  test "the original poster can reopen a Solved post" do
    Current.set(user: users(:kevin)) { @post.solve! }
    sign_in :kevin

    delete rooms_forum_post_solution_url(@forum, @post)

    assert_not @post.reload.solved?
  end

  test "a non-OP non-admin member cannot mark Solved (AE1 restriction)" do
    sign_in :jz

    assert_no_changes -> { @post.reload.solved? } do
      post rooms_forum_post_solution_url(@forum, @post)
    end

    assert_response :forbidden
  end

  test "a deleted post cannot be marked Solved through the nested route" do
    @post.deactivate

    post rooms_forum_post_solution_url(@forum, @post)

    assert_redirected_to room_url(@forum)
    assert_not @post.reload.solved?
  end

  test "a post can be marked Solved with only its opening message (no replies)" do
    sign_in :kevin
    assert_equal 0, @post.replies_count
    assert_equal 1, @post.messages_count, "just the opening message"

    post rooms_forum_post_solution_url(@forum, @post)

    assert @post.reload.solved?
  end

  test "marking Solved broadcasts to the tenant-scoped gallery and post streams" do
    sign_in :kevin

    assert_turbo_stream_broadcasts [ @forum, :posts ], count: 1 do
      assert_turbo_stream_broadcasts [ @post, :messages ], count: 1 do
        post rooms_forum_post_solution_url(@forum, @post)
      end
    end
  end

  test "the Solved toggle is shown to the OP but not to a plain member" do
    sign_in :kevin
    get rooms_post_url(@post)
    assert_select "form[action=?]", rooms_forum_post_solution_path(@forum, @post)

    sign_in :jz
    get rooms_post_url(@post)
    assert_select "form[action=?]", rooms_forum_post_solution_path(@forum, @post), count: 0
  end

  test "a reply in a post refreshes the gallery card live" do
    assert_turbo_stream_broadcasts [ @forum, :posts ], count: 1 do
      Current.set(user: users(:kevin)) do
        @post.messages.create!(body: "<div>a reply</div>", creator: users(:kevin))
      end
    end
  end

  test "a reply broadcasts the reply-count update to the post's own stream (panel + page)" do
    assert_turbo_stream_broadcasts [ @post, :messages ], count: 1 do
      Current.set(user: users(:kevin)) do
        @post.messages.create!(body: "<div>a reply</div>", creator: users(:kevin))
      end
    end
  end
end
