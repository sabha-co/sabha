require "test_helper"

class Inboxes::PagedControllersTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @david = users(:david)
    @jason = users(:jason)
  end

  # ===================
  # Paged Activity
  # ===================

  test "paged activity returns success" do
    get paged_inbox_activity_index_url
    assert_response :success
  end

  test "paged activity returns messages mentioning user" do
    room = rooms(:pets)
    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} paged mention marker</div>",
      creator: @jason,
      client_message_id: "paged_mention_1"
    )

    get paged_inbox_activity_index_url
    assert_response :success
    assert_match "paged mention marker", response.body
  end

  test "paged activity supports pagination" do
    room = rooms(:pets)
    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "paged_mention_paginate"
    )

    notification = Notification.where(user: @david, activity_type: "mention").order(:created_at).last
    get paged_inbox_activity_index_url, params: { before: notification.id }
    assert_response :success
  end

  # ===================
  # Paged Threads
  # ===================

  test "paged threads returns success" do
    get paged_inbox_threads_url
    assert_response :success
  end

  test "paged threads returns thread parent messages" do
    room = rooms(:pets)
    parent_message = room.messages.create!(
      body: "Paged thread parent marker",
      creator: @jason,
      client_message_id: "paged_parent_1"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :everything)
    thread.messages.create!(body: "Reply", creator: @david, client_message_id: "paged_reply_1")

    get paged_inbox_threads_url
    assert_response :success
    assert_match "Paged thread parent marker", response.body
  end

  # ===================
  # Paged Notifications
  # ===================

  test "paged notifications returns success" do
    get paged_inbox_notifications_url
    assert_response :success
  end

  test "paged notifications returns messages from rooms with notifications_on involvement" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: @david)
    membership.update!(involvement: :everything)

    room.messages.create!(
      body: "Paged notification marker",
      creator: @jason,
      client_message_id: "paged_notification_1"
    )

    get paged_inbox_notifications_url
    assert_response :success
    assert_match "Paged notification marker", response.body
  end

  # ===================
  # Paged Messages
  # ===================

  test "paged messages returns success" do
    get paged_inbox_messages_url
    assert_response :success
  end

  test "paged messages returns messages from visible rooms" do
    room = rooms(:pets)
    room.messages.create!(
      body: "Paged message marker",
      creator: @jason,
      client_message_id: "paged_message_1"
    )

    get paged_inbox_messages_url
    assert_response :success
    assert_match "Paged message marker", response.body
  end

  # ===================
  # Paged Bookmarks
  # ===================

  test "paged bookmarks returns success" do
    get paged_inbox_bookmarks_url
    assert_response :success
  end

  test "paged bookmarks returns bookmarked messages" do
    message = messages(:first)
    message.update!(body: "Paged bookmark marker")
    Bookmark.create!(user: @david, message: message)

    get paged_inbox_bookmarks_url
    assert_response :success
    assert_match "Paged bookmark marker", response.body
  end

  # ===================
  # Paged Direct Messages
  # ===================

  test "paged direct messages returns success" do
    get paged_inbox_direct_messages_url
    assert_response :success
  end

  test "paged direct messages returns no content when empty" do
    # Remove all direct room memberships for david
    @david.memberships.direct_rooms.destroy_all

    get paged_inbox_direct_messages_url
    assert_response :no_content
  end

  test "paged direct messages supports pagination with before param" do
    dm = rooms(:david_and_jason)
    dm.touch(:last_active_at)

    get paged_inbox_direct_messages_url, params: { before: dm.id }
    # Should return no content since this DM is likely the most recent
    assert_response :no_content
  end

  test "paged direct messages supports pagination with after param" do
    dm = rooms(:david_and_jason)
    dm.touch(:last_active_at)

    get paged_inbox_direct_messages_url, params: { after: dm.id }
    # May return success or no_content depending on data
    assert_includes [ 200, 204 ], response.status
  end
end
