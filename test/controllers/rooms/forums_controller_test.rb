require "test_helper"

class Rooms::ForumsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "new renders the forum form" do
    get new_rooms_forum_url

    assert_response :success
    assert_select "form[action=?]", rooms_forums_path
    assert_select "input[name='room[name]']"
  end

  test "create makes a forum, auto-joins every active user, broadcasts a sidebar add to the creator, and redirects" do
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
      post rooms_forums_url, params: { room: { name: "Support Forum" } }
    end

    forum = Room.last
    assert forum.forum?
    assert_equal User.active.count, forum.memberships.count
    assert_includes forum.users, users(:david)
    assert_redirected_to room_url(forum)
  end

  test "the forum renders its gallery at the canonical room URL" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get room_url(forum)

    assert_response :success
    assert_select ".forum"
  end

  # Regression: creating a forum or post redirects to the gallery, and Turbo
  # follows that redirect with a turbo-stream Accept header but no page param.
  # Without disambiguating on the page param, show served the pagination fragment
  # (an append against an off-page target), so the browser never navigated and
  # creation looked like it silently failed.
  test "a turbo-stream visit without a page param renders the full gallery page" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get room_url(forum), as: :turbo_stream

    assert_response :success
    assert_select ".forum"
    assert_select "turbo-stream[action=append]", count: 0
  end

  test "a paginated turbo-stream request renders the append stream" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }

    get room_url(forum, page: 1), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=append]"
  end

  test "the namespaced forum path redirects to the canonical room URL" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get rooms_forum_url(forum)

    assert_redirected_to room_url(forum)
  end

  test "the gallery renders a card per post with title, Solved badge, and a panel link" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    Current.set(user: users(:david)) do
      forum.post!(title: "First question", body: "<div>Body one</div>")
      forum.post!(title: "Second question", body: "<div>Body two</div>").solve!
    end

    get room_url(forum)

    assert_response :success
    assert_select ".forum-card", count: 2
    assert_select ".forum-card__title", text: "First question"
    assert_select ".forum-tag--solved", text: /Solved/
    assert_select "a.forum-card[data-turbo-frame='thread_panel_frame']", count: 2
  end

  test "a post deep-link points the panel frame at the post so it opens over the gallery" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Deep link", body: "<div>b</div>") }

    get room_url(forum, post: post.slug)

    assert_response :success
    assert_select ".forum"
    assert_select "turbo-frame#thread_panel_frame[src=?]", rooms_post_path(post)
  end

  test "a post deep-link forwards a reply anchor to the panel frame" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    post = Current.set(user: users(:david)) { forum.post!(title: "Deep link", body: "<div>b</div>") }
    reply = post.messages.create!(body: "<div>a reply</div>", creator: users(:david))

    get room_url(forum, post: post.slug, message_id: reply.id)

    assert_select "turbo-frame#thread_panel_frame[src=?]", rooms_post_path(post, message_id: reply.id)
  end

  test "an unknown post slug renders the plain gallery with no panel frame src" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get room_url(forum, post: "no-such-post")

    assert_response :success
    assert_select ".forum"
    assert_select "turbo-frame#thread_panel_frame:not([src])"
  end

  test "an empty forum shows the empty state and the New post composer" do
    forum = Rooms::Forum.create_for({ name: "Quiet", creator: users(:david) }, users: users(:david))

    get room_url(forum)

    assert_select ".forum__empty"
    assert_select "details.forum-compose > summary", text: /New post/
  end

  test "gallery cards are ordered by most recent activity" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    older = newer = nil
    Current.set(user: users(:david)) do
      older = forum.post!(title: "Older post", body: "<div>b</div>")
      newer = forum.post!(title: "Newer post", body: "<div>b</div>")
    end
    older.update!(last_active_at: 2.hours.ago)
    newer.update!(last_active_at: 1.minute.ago)

    get room_url(forum)

    titles = css_select(".forum-card__title").map(&:text)
    assert_equal [ "Newer post", "Older post" ], titles
  end

  test "a Solved filter matching nothing renders the empty-filter state with the bar still present" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    Current.set(user: users(:david)) { forum.post!(title: "Open post", body: "<div>b</div>") }

    get room_url(forum, solved: "solved")

    assert_response :success
    assert_select ".forum-card", count: 0
    assert_select ".forum__empty", text: /Nothing matches these filters/
    assert_select ".forum-filter"
  end

  test "the filter bar reflects the active Solved state" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }

    get room_url(forum, solved: "open")

    assert_select ".forum-seg__btn--active", text: "Open"
  end

  test "admin sees the forum edit form" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get edit_rooms_forum_url(forum)

    assert_response :success
    assert_select "input[name='room[name]']"
  end

  test "the forum edit page has no public/private access toggle" do
    # The access switch only knows Open<->Closed; toggling it on a forum would
    # becomes!(Rooms::Open) and orphan the posts, so it must not render here.
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get edit_rooms_forum_url(forum)

    assert_response :success
    assert_select "form[action=?]", room_access_path(forum), count: 0
  end

  test "a non-admin non-creator cannot edit or update the forum" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: [ users(:david), users(:kevin) ])

    sign_in :kevin
    get edit_rooms_forum_url(forum)
    assert_response :forbidden

    put rooms_forum_url(forum), params: { room: { name: "Hijacked" } }
    assert_response :forbidden
    assert_equal "Docs", forum.reload.name
  end

  test "non-admin cannot create a forum when creation is restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!
    sign_in :jz

    get new_rooms_forum_url
    assert_response :forbidden

    post rooms_forums_url, params: { room: { name: "Nope" } }
    assert_response :forbidden
  end

  test "admin can destroy the forum" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_forum_url(forum)
    end

    assert_redirected_to root_url
  end

  # --- Review-hardening -------------------------------------------------------

  test "the Solved filter shows only solved posts" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    Current.set(user: users(:david)) do
      forum.post!(title: "Solved one", body: "<div>b</div>").solve!
      forum.post!(title: "Open one", body: "<div>b</div>")
    end

    get room_url(forum, solved: "solved")

    assert_equal [ "Solved one" ], css_select(".forum-card__title").map(&:text)
  end

  test "the newest sort orders by creation, distinct from recent activity" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    first = second = nil
    Current.set(user: users(:david)) do
      first = forum.post!(title: "First created", body: "<div>b</div>")
      second = forum.post!(title: "Second created", body: "<div>b</div>")
    end
    first.update!(last_active_at: 1.minute.ago)
    second.update!(last_active_at: 2.hours.ago)

    get room_url(forum, sort: "recent")
    assert_equal [ "First created", "Second created" ], css_select(".forum-card__title").map(&:text)

    get room_url(forum, sort: "newest")
    assert_equal [ "Second created", "First created" ], css_select(".forum-card__title").map(&:text)
  end

  test "an admin rename persists without writing an orphaned announcement" do
    forum = Rooms::Forum.create_for({ name: "Old Name", creator: users(:david) }, users: users(:david))

    # A forum renders a gallery, not a message stream, so the rename must not
    # post a room_renamed event message that nothing would display.
    assert_no_difference -> { Message.unscoped.where(room: forum, event: "room_renamed").count } do
      put rooms_forum_url(forum), params: { room: { name: "New Name" } }
    end

    assert_equal "New Name", forum.reload.name
  end

  test "the gallery paginates and lazy-loads further posts" do
    forum = Rooms::Forum.create_for({ name: "Busy", creator: users(:david) }, users: users(:david))
    21.times { |i| Rooms::Post.create!(parent_room: forum, name: "Post #{i}", creator: users(:david)) }

    get room_url(forum)
    assert_response :success
    assert_select "a.forum-card", count: 20
    assert_select "turbo-frame#next_page_container"

    get room_url(forum, page: 2, format: :turbo_stream)
    assert_response :success
    assert_match "forum-card", response.body
  end

  test "a removed member is bounced from the forum gallery" do
    forum = Rooms::Forum.create_for({ name: "Members only", creator: users(:david) }, users: users(:david))
    forum.remove_member!(users(:kevin), actor: users(:david)) # auto-joined, then removed
    sign_in :kevin

    get room_url(forum)

    assert_redirected_to root_url
  end
end
