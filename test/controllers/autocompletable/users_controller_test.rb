require "test_helper"

class Autocompletable::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "search returns matching users" do
    get autocompletable_users_url(format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David", response.parsed_body.first["name"]
  end

  test "search results escape HTML in names" do
    users(:david).update!(name: "David <script>alert(123)</script>")

    get autocompletable_users_url(format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David &lt;script&gt;alert(123)&lt;/script&gt;", response.parsed_body.first["name"]
  end

  test "room search returns matching users" do
    get autocompletable_users_url(room_id: rooms(:hq).id, format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David", response.parsed_body.first["name"]
  end

  test "room search is scoped by membership" do
    sign_in :kevin

    assert_not_includes users(:kevin).rooms, rooms(:watercooler)

    assert_raises ActiveRecord::RecordNotFound do
      get autocompletable_users_url(room_id: rooms(:watercooler).id, format: :json), params: { query: "da" }
    end
  end

  test "forum post autocomplete resolves via forum access and suggests forum members" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
    post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }

    sign_in :kevin
    assert_not Membership.exists?(room_id: post.id, user_id: users(:kevin).id), "kevin is a forum member, not a post follower"

    get autocompletable_users_url(room_id: post.id, format: :json), params: { query: "da" }

    assert_response :success
    assert_includes response.parsed_body.map { |u| u["name"] }, "David"
  end

  test "a member removed from the parent room cannot enumerate the roster via the thread mention picker" do
    room = rooms(:pets)
    parent = room.messages.create!(body: "topic", creator: users(:david))
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    Current.set(user: users(:jason)) { thread.messages.create!(body: "in", creator: users(:jason)) }

    room.remove_member!(users(:jason), actor: users(:david))

    # jason's thread membership is still active (only silenced), so it resolves
    # via Current.user.rooms — the viewable_by? re-check must deny the picker.
    sign_in :jason
    assert_raises ActiveRecord::RecordNotFound do
      get autocompletable_users_url(room_id: thread.id, format: :json), params: { query: "da" }
    end
  end

  test "user_ids scopes suggestions to the chosen recipients (provisional DM mention picker)" do
    # A provisional DM has no room yet, so its composer scopes @-mentions to the
    # recipients. A non-recipient must not surface — selecting one would render a
    # mention that never notifies them once the DM is created.
    get autocompletable_users_url(user_ids: [ users(:jz).id ], format: :json), params: { query: "" }

    assert_response :success
    ids = response.parsed_body.map { |u| u["value"] }
    assert_includes ids, users(:jz).id
    assert_not_includes ids, users(:kevin).id
  end

  test "blank query returns recent users (mention picker default)" do
    get autocompletable_users_url(format: :json), params: { query: "" }

    assert_response :success
    assert response.parsed_body.is_a?(Array)
    assert response.parsed_body.size > 0, "blank query should populate the @-mention picker"
  end

  test "mention prompt (html) returns lexxy-prompt-item elements filtered by `filter`" do
    get autocompletable_users_url(room_id: rooms(:hq).id, format: :html), params: { filter: "da" }

    assert_response :success
    assert_match %r{<lexxy-prompt-item[^>]*sgid=}, response.body
    assert_match %r{<template type="menu">}, response.body
    assert_match %r{class="mention"}, response.body
    assert_match %r{David}, response.body
  end

  test "mention prompt offers @everyone to an admin in an open room when it matches the filter" do
    room = Rooms::Open.create_for({ name: "Open Space", creator: users(:david) }, users: [ users(:david) ])

    get autocompletable_users_url(room_id: room.id, format: :html), params: { filter: "every" }
    assert_response :success
    assert_match %r{mention--everyone}, response.body

    get autocompletable_users_url(room_id: room.id, format: :html), params: { filter: "zzz" }
    assert_response :success
    assert_no_match %r{mention--everyone}, response.body
  end

  test "exact first name matches appear before partial matches" do
    davidson = User.create!(name: "Davidson Smith", email_address: "davidson@example.com", password: "secret123456", verified_at: 1.day.ago)

    get autocompletable_users_url(format: :json), params: { query: "David" }

    assert_response :success
    names = response.parsed_body.map { |u| u["name"] }

    assert_includes names, "David"
    assert_includes names, "Davidson Smith"
    assert names.index("David") < names.index("Davidson Smith"), "Exact first name match 'David' should appear before partial match 'Davidson Smith'"
  end
end
