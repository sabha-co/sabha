require "test_helper"

class Rooms::PostTest < ActiveSupport::TestCase
  setup do
    @forum = rooms(:help_desk)
  end

  test "a post stores its title in name and belongs to its forum" do
    post = create_post(title: "How do I reset my password?")

    assert post.persisted?
    assert post.post?
    assert_equal "How do I reset my password?", post.title
    assert_equal "How do I reset my password?", post.name
    assert_equal @forum, post.parent_room
  end

  test "a post requires a title" do
    post = Rooms::Post.new(parent_room: @forum, creator: users(:david))

    assert_not post.valid?
    assert post.errors[:name].present?
  end

  test "a post gets a URL-safe slug derived from its title" do
    post = create_post(title: "How do I reset my password?")
    assert_equal "how-do-i-reset-my-password", post.slug
  end

  test "two posts with the same title get distinct slugs" do
    first = create_post(title: "Setup guide")
    second = create_post(title: "Setup guide")

    assert_not_equal first.slug, second.slug
    assert_equal "setup-guide", first.slug
    assert_equal "setup-guide-2", second.slug
  end

  test "a post slug is permanent across a later rename" do
    post = create_post(title: "Original title")
    original_slug = post.slug

    post.update!(name: "Completely different title")

    assert_equal original_slug, post.slug
  end

  # --- Solved as a record (Solution) -----------------------------------------

  test "solving creates a Solution carrying who solved it and when" do
    post = create_post(title: "Broken webhook")
    assert_not post.solved?

    solver = users(:david)
    Current.set(user: solver) do
      assert_difference -> { Solution.count }, 1 do
        post.solve!
      end
    end

    assert post.solved?
    assert_equal solver, post.solved_by
    assert post.solved_at.present?
  end

  test "reopening destroys the Solution" do
    post = create_post(title: "Broken webhook")
    Current.set(user: users(:david)) { post.solve! }
    assert post.solved?

    assert_difference -> { Solution.count }, -1 do
      post.reopen!
    end

    assert_not post.solved?
    assert_nil post.solved_at
    assert_nil post.solved_by
  end

  test "solving twice keeps a single Solution" do
    post = create_post(title: "Broken webhook")

    Current.set(user: users(:david)) do
      post.solve!
      assert_no_difference -> { Solution.count } do
        post.solve!
      end
    end

    assert post.solved?
  end

  test "solved and unsolved scopes partition posts by Solution presence" do
    solved_post = create_post(title: "Answered")
    open_post = create_post(title: "Still open")
    Current.set(user: users(:david)) { solved_post.solve! }

    assert_includes Rooms::Post.solved, solved_post
    assert_not_includes Rooms::Post.solved, open_post
    assert_includes Rooms::Post.unsolved, open_post
    assert_not_includes Rooms::Post.unsolved, solved_post
  end

  # --- Access derived from the forum (D2) ------------------------------------

  test "a post is viewable by a forum member and not by a non-member" do
    member = users(:jason)
    non_member = users(:kevin)
    @forum.memberships.grant_to(member)

    post = create_post(title: "Members only")

    assert post.viewable_by?(member)
    assert_not post.viewable_by?(non_member)
    assert_not post.viewable_by?(nil)
  end

  test "default involvement is everything for the author, invisible for others" do
    author = users(:david)
    post = create_post(title: "Mine", author: author)

    assert_equal "everything", post.default_involvement(user: author)
    assert_equal "invisible", post.default_involvement(user: users(:jason))
    assert_equal "invisible", post.default_involvement(user: nil)
  end

  # --- Broadcasts -------------------------------------------------------------

  test "renaming a post broadcasts its gallery card" do
    post = create_post(title: "Before")

    assert_turbo_stream_broadcasts [ @forum, :posts ], count: 1 do
      post.update!(name: "After")
    end
  end

  test "solving a post broadcasts its gallery card" do
    post = create_post(title: "Broken webhook")

    Current.set(user: users(:david)) do
      assert_turbo_stream_broadcasts [ @forum, :posts ], count: 1 do
        post.solve!
      end
    end
  end

  # --- Scale contract: no membership fan-out (D2) ----------------------------

  test "post! grants a membership to the author only, not to every forum member" do
    @forum.memberships.grant_to([ users(:jason), users(:jz), users(:kevin) ])

    post = Current.set(user: users(:david)) { @forum.post!(title: "Scale", body: "Body") }

    author_memberships = Membership.where(room_id: post.id)
    assert_equal [ users(:david).id ], author_memberships.pluck(:user_id)
    assert_equal "everything", author_memberships.first.involvement
  end

  test "a forum member can view a post without holding a post membership" do
    member = users(:jason)
    @forum.memberships.grant_to(member)

    post = Current.set(user: users(:david)) { @forum.post!(title: "Q", body: "b") }

    assert_not Membership.exists?(room_id: post.id, user_id: member.id), "no per-post membership row"
    assert post.viewable_by?(member), "access derives from forum membership"
  end

  test "replying lazily creates the replier's membership without downgrading an existing follower" do
    replier = users(:jason)
    @forum.memberships.grant_to(replier)
    post = Current.set(user: users(:david)) { @forum.post!(title: "Q", body: "b") }
    assert_not Membership.exists?(room_id: post.id, user_id: replier.id)

    Current.set(user: replier) { post.messages.create!(body: "my reply", creator: replier) }

    membership = Membership.find_by(room_id: post.id, user_id: replier.id)
    assert membership.present?, "replying creates a lazy membership"
    assert_equal "everything", membership.involvement

    # A follower who dialed themselves down is not re-upgraded by replying again.
    membership.update!(involvement: "mentions")
    Current.set(user: replier) { post.messages.create!(body: "again", creator: replier) }
    assert_equal "mentions", membership.reload.involvement
  end

  test "joining a forum that already has posts creates zero post memberships" do
    Current.set(user: users(:david)) do
      @forum.post!(title: "One", body: "b")
      @forum.post!(title: "Two", body: "b")
    end
    post_scope = Membership.where(room_id: Rooms::Post.where(parent_room_id: @forum.id))

    assert_no_difference -> { post_scope.count } do
      @forum.accept_join!(users(:jason))
    end
  end

  test "leaving a forum silences that member's post follows but not other members'" do
    leaver = users(:jason)
    stayer = users(:kevin)
    @forum.memberships.grant_to([ leaver, stayer ])
    post = Current.set(user: users(:david)) { @forum.post!(title: "Q", body: "b") }
    Current.set(user: leaver) { post.messages.create!(body: "l", creator: leaver) }
    Current.set(user: stayer) { post.messages.create!(body: "s", creator: stayer) }

    perform_enqueued_jobs { @forum.accept_leave!(leaver) }

    assert_equal "invisible", Membership.find_by(room_id: post.id, user_id: leaver.id).involvement
    assert_equal "everything", Membership.find_by(room_id: post.id, user_id: stayer.id).involvement
  end

  test "destroying a user who marked a post Solved removes the Solution (no FK block)" do
    post = create_post(title: "Answered")
    solver = users(:jason)
    Current.set(user: solver) { post.solve! }
    assert Solution.exists?(user_id: solver.id)

    assert_nothing_raised { solver.destroy }
    assert_not Solution.exists?(user_id: solver.id)
  end

  test "deleting a post destroys notifications tied to its messages" do
    post = Current.set(user: users(:david)) { @forum.post!(title: "Answered", body: "b") }
    message = post.messages.first
    Notification.create!(user: users(:jason), message: message, actor: users(:david), activity_type: "thread_reply")

    assert_difference -> { Notification.where(message_id: message.id).count }, -1 do
      post.deactivate
    end
  end

  private
    def create_post(title:, author: users(:david))
      Rooms::Post.create!(parent_room: @forum, name: title, creator: author)
    end
end
