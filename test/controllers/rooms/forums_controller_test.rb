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

  test "create makes a forum, grants creator membership, broadcasts one sidebar add, and redirects" do
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
      post rooms_forums_url, params: { room: { name: "Support Forum" } }
    end

    forum = Room.last
    assert forum.forum?
    assert_equal 1, forum.memberships.count
    assert_includes forum.users, users(:david)
    assert_redirected_to rooms_forum_url(forum)
  end

  test "create with a starter tag list persists forum-scoped tags" do
    post rooms_forums_url, params: { room: { name: "Help Desk", tags: "Question, Bug, Setup" } }
    forum = Room.last

    assert_equal %w[Bug Question Setup], forum.tags.ordered.pluck(:name)
    forum.tags.each { |tag| assert_equal forum.id, tag.room_id }
  end

  test "tags are forum-scoped: forum A's tag is absent from forum B (AE4)" do
    forum_a = Rooms::Forum.create_for({ name: "A", creator: users(:david) }, users: users(:david))
    forum_b = Rooms::Forum.create_for({ name: "B", creator: users(:david) }, users: users(:david))

    post rooms_forum_tags_url(forum_a), params: { tag: { name: "Question" } }

    assert_equal %w[Question], forum_a.tags.pluck(:name)
    assert_empty forum_b.tags
  end

  test "show redirects the generic room path to the forum gallery" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get room_url(forum)

    assert_redirected_to rooms_forum_url(forum)
  end

  test "show renders the gallery for a member" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))

    get rooms_forum_url(forum)

    assert_response :success
  end

  test "the gallery renders a card per post with title, tags, Solved badge, and a panel link" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    tag = forum.tags.create!(name: "Question")
    Current.set(user: users(:david)) do
      forum.post!(title: "First question", body: "<div>Body one</div>", tag_ids: [ tag.id ])
      forum.post!(title: "Second question", body: "<div>Body two</div>").mark_solved!
    end

    get rooms_forum_url(forum)

    assert_response :success
    assert_select ".forum-card", count: 2
    assert_select ".forum-card__title", text: "First question"
    assert_select ".forum-tag", text: /Question/
    assert_select ".forum-tag--solved", text: /Solved/
    assert_select "a.forum-card[data-turbo-frame='thread_panel_frame']", count: 2
  end

  test "an empty forum shows the empty-state CTA" do
    forum = Rooms::Forum.create_for({ name: "Quiet", creator: users(:david) }, users: users(:david))

    get rooms_forum_url(forum)

    assert_select ".forum__empty"
    assert_select ".forum__empty a[href=?]", new_rooms_forum_post_path(forum)
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

    get rooms_forum_url(forum)

    titles = css_select(".forum-card__title").map(&:text)
    assert_equal [ "Newer post", "Older post" ], titles
  end

  test "filtering by tag and Solved composes (AE2)" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    question = forum.tags.create!(name: "Question")
    bug = forum.tags.create!(name: "Bug")
    Current.set(user: users(:david)) do
      forum.post!(title: "Solved question", body: "<div>b</div>", tag_ids: [ question.id ]).mark_solved!
      forum.post!(title: "Open question", body: "<div>b</div>", tag_ids: [ question.id ])
      forum.post!(title: "A bug", body: "<div>b</div>", tag_ids: [ bug.id ])
    end

    get rooms_forum_url(forum, tag_ids: [ question.id ], solved: "open")

    assert_equal [ "Open question" ], css_select(".forum-card__title").map(&:text)
  end

  test "composing two tags returns posts having either tag (OR semantics)" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    question = forum.tags.create!(name: "Question")
    bug = forum.tags.create!(name: "Bug")
    Current.set(user: users(:david)) do
      forum.post!(title: "A question", body: "<div>b</div>", tag_ids: [ question.id ])
      forum.post!(title: "A bug", body: "<div>b</div>", tag_ids: [ bug.id ])
      forum.post!(title: "Untagged", body: "<div>b</div>")
    end

    get rooms_forum_url(forum, tag_ids: [ question.id, bug.id ])

    assert_equal [ "A bug", "A question" ], css_select(".forum-card__title").map(&:text).sort
  end

  test "a filter matching nothing renders the empty-filter state with the bar still present" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    question = forum.tags.create!(name: "Question")
    Current.set(user: users(:david)) { forum.post!(title: "Untagged post", body: "<div>b</div>") }

    get rooms_forum_url(forum, tag_ids: [ question.id ])

    assert_response :success
    assert_select ".forum-card", count: 0
    assert_select ".forum__empty", text: /Nothing matches these filters/
    assert_select ".forum-filter"
  end

  test "the filter bar reflects the active tag and Solved state" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    question = forum.tags.create!(name: "Question")
    Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>", tag_ids: [ question.id ]) }

    get rooms_forum_url(forum, tag_ids: [ question.id ], solved: "open")

    assert_select ".forum-filter__chip--active", text: /Question/
    assert_select ".forum-seg__btn--active", text: "Open"
  end

  test "admin sees the forum edit form with tag curation" do
    forum = Rooms::Forum.create_for({ name: "Docs", creator: users(:david) }, users: users(:david))
    forum.tags.create!(name: "Question")

    get edit_rooms_forum_url(forum)

    assert_response :success
    assert_select "form[action=?]", rooms_forum_tags_path(forum)
    assert_select "input[name='tag[name]']"
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

  test "non-admin cannot create a forum when creation is restricted to admins" do
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
end
