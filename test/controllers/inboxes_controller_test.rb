require "test_helper"

class InboxesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @david = users(:david)
    @jason = users(:jason)
    @jz = users(:jz)
  end

  # ===================
  # Show action tests
  # ===================

  test "show redirects to activity" do
    get inbox_url
    assert_redirected_to activity_inbox_path
  end

  test "show clears last loaded message timestamps" do
    # Set some session values first by visiting activity
    get activity_inbox_url
    assert_response :success

    # Now visit show - should clear timestamps and redirect
    get inbox_url
    assert_redirected_to activity_inbox_path
  end

  # ===================
  # Activity tests
  # ===================

  test "activity returns success" do
    get activity_inbox_url
    assert_response :success
  end

  test "activity shows messages mentioning current user" do
    room = rooms(:pets)

    # Create a message that mentions david
    message_with_mention = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} unique marker 12345</div>",
      creator: @jason,
      client_message_id: "mention_test_1"
    )

    get activity_inbox_url
    assert_response :success
    # The mention is rendered as HTML, check for the unique marker text
    assert_match "unique marker 12345", response.body
  end

  test "activity excludes messages created by current user" do
    room = rooms(:pets)

    # Create a message where david mentions himself
    self_mention = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} self mention</div>",
      creator: @david,
      client_message_id: "self_mention_test"
    )

    get activity_inbox_url
    assert_response :success
    # Self-created messages should not appear
    assert_no_match "self mention", response.body
  end

  test "activity excludes direct messages" do
    dm_room = rooms(:david_and_jason)
    dm_message = dm_room.messages.create!(
      body: "Hey David direct message excluded!",
      creator: @jason,
      client_message_id: "dm_test_1"
    )

    get activity_inbox_url
    assert_response :success
    assert_no_match "Hey David direct message excluded!", response.body
  end

  test "activity shows boost notifications" do
    room = rooms(:pets)

    # Create a message by david, then boost it from jason
    message = room.messages.create!(
      body: "My boosted message content",
      creator: @david,
      client_message_id: "boost_activity_test"
    )
    boost = message.boosts.create!(content: "🔥", booster: @jason)

    get activity_inbox_url
    assert_response :success
    assert_match "boosted your message", response.body
    assert_match @jason.name, response.body
  end

  test "activity shows thread reply notifications" do
    room = rooms(:pets)

    # Create a parent message
    parent = room.messages.create!(
      body: "Parent for thread reply test",
      creator: @jason,
      client_message_id: "thread_parent_1"
    )

    # Create a thread with david as a visible member
    thread = Rooms::Thread.create!(parent_message: parent, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :mentions)

    # Reply in the thread
    reply = thread.messages.create!(
      body: "Thread reply visible in activity",
      creator: @jason,
      client_message_id: "thread_reply_1"
    )

    # The job creates notifications synchronously in test
    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: @jason.id
    )

    get activity_inbox_url
    assert_response :success
    assert_match "Thread reply visible in activity", response.body
  end

  test "activity shows all notifications" do
    room = rooms(:pets)

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} all visible</div>",
      creator: @jason,
      client_message_id: "all_visible"
    )

    get activity_inbox_url
    post clear_inbox_url, params: { scope: "activity", stay: true }

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} also visible</div>",
      creator: @jason,
      client_message_id: "also_visible"
    )

    # Both should appear
    get activity_inbox_url
    assert_response :success
    assert_match "all visible", response.body
    assert_match "also visible", response.body
  end

  test "mentioning a non-member does not add them to the room" do
    sign_in :kevin
    kevin = users(:kevin)
    room = rooms(:pets)

    assert_not room.users.include?(kevin), "Kevin should not be a member of pets initially"

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)} this mention should not add you</div>",
      creator: @jason,
      client_message_id: "no_involve_test"
    )

    room.reload
    assert_not room.users.include?(kevin), "Kevin should still not be a member after being mentioned"
  end

  # ===================
  # Direct Messages tests
  # ===================

  test "direct_messages returns success" do
    get direct_messages_inbox_url
    assert_response :success
  end

  test "direct_messages shows DM rooms for current user" do
    dm_room = rooms(:david_and_jason)

    get direct_messages_inbox_url
    assert_response :success
    assert_select ".dm-conversation"
  end

  test "direct_messages excludes inactive DM rooms" do
    dm_room = rooms(:david_and_jason)
    dm_room.update!(active: false)

    get direct_messages_inbox_url
    assert_response :success
    # The deactivated room should not be present
    assert_select "#dm_inbox_room_#{dm_room.id}", count: 0
  end

  test "direct_messages shows member names" do
    dm_room = rooms(:david_and_jason)

    get direct_messages_inbox_url
    assert_response :success
    assert_match @jason.name, response.body
  end

  # ===================
  # Threads tests
  # ===================

  test "threads returns success" do
    get threads_inbox_url
    assert_response :success
  end

  test "threads shows parent messages of threads user has visible membership in" do
    room = rooms(:pets)

    # Create a parent message
    parent_message = room.messages.create!(
      body: "Parent message for thread visibility test",
      creator: @jason,
      client_message_id: "parent_1"
    )

    # Create a thread and give david visible membership
    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :everything)

    # Add a message to the thread so it has messages_count > 0
    thread.messages.create!(body: "Thread reply", creator: @david, client_message_id: "reply_1")

    get threads_inbox_url
    assert_response :success
    assert_match "Parent message for thread visibility test", response.body
  end

  test "threads shows parent messages for users with everything involvement in parent room" do
    room = rooms(:pets)

    # David has "everything" involvement in pets room
    membership = room.memberships.find_by(user: @david)
    membership.update!(involvement: :everything)

    # Create a parent message
    parent_message = room.messages.create!(
      body: "Parent message everything involvement",
      creator: @jason,
      client_message_id: "parent_2"
    )

    # Create a thread (david doesn't need direct membership due to parent room involvement)
    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    thread.memberships.grant_to(@jason)
    thread.messages.create!(body: "Thread reply", creator: @jason, client_message_id: "reply_2")

    get threads_inbox_url
    assert_response :success
    assert_match "Parent message everything involvement", response.body
  end

  test "threads excludes threads with no messages" do
    room = rooms(:pets)

    parent_message = room.messages.create!(
      body: "Parent with empty thread marker",
      creator: @jason,
      client_message_id: "parent_empty"
    )

    # Create a thread but don't add any messages
    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :everything)

    get threads_inbox_url
    assert_response :success
    assert_no_match "Parent with empty thread marker", response.body
  end

  test "threads excludes threads from inaccessible rooms" do
    sign_in :kevin

    room = rooms(:designers) # kevin has membership but not "everything" involvement

    parent_message = room.messages.create!(
      body: "Designer thread parent marker",
      creator: @jason,
      client_message_id: "designer_parent"
    )

    thread = Rooms::Thread.create!(parent_message: parent_message, creator: @jason)
    thread.memberships.grant_to(@jason)
    thread.messages.create!(body: "Reply", creator: @jason, client_message_id: "designer_reply")

    get threads_inbox_url
    assert_response :success
    assert_no_match "Designer thread parent marker", response.body
  end

  # ===================
  # Bookmarks tests
  # ===================

  test "bookmarks returns success" do
    get bookmarks_inbox_url
    assert_response :success
  end

  test "bookmarks shows bookmarked messages for current user" do
    message = messages(:first)
    message.update!(body: "Bookmarked message marker")
    Bookmark.create!(user: @david, message: message)

    get bookmarks_inbox_url
    assert_response :success
    assert_match "Bookmarked message marker", response.body
  end

  test "bookmarks excludes inactive messages" do
    message = messages(:first)
    message.update!(body: "Inactive message marker")
    Bookmark.create!(user: @david, message: message)
    message.update!(active: false)

    get bookmarks_inbox_url
    assert_response :success
    assert_no_match "Inactive message marker", response.body
  end

  test "bookmarks excludes other users bookmarks" do
    message = messages(:first)
    message.update!(body: "Other user bookmark marker")
    Bookmark.create!(user: @jason, message: message)

    get bookmarks_inbox_url
    assert_response :success
    assert_no_match "Other user bookmark marker", response.body
  end

  # ===================
  # Clear action tests
  # ===================

  test "clear marks memberships as read" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: @david)
    membership.update!(unread_at: 1.hour.ago)

    # Create a mention so mark_activity_as_read finds a notified room
    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "clear_test_mention"
    )

    # First visit activity to set the session timestamp
    get activity_inbox_url

    # Then clear
    post clear_inbox_url
    assert_redirected_to activity_inbox_path

    membership.reload
    assert membership.read?, "Membership should be marked as read"
  end

  test "clear stays on page when stay param is present" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: @david)
    membership.update!(unread_at: 1.hour.ago)

    get activity_inbox_url
    post clear_inbox_url, params: { stay: true }
    assert_response :success
  end

  test "clear with scope activity only clears rooms with activity" do
    # Room with mention
    room_with_mention = rooms(:pets)
    room_with_mention.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason
    )
    membership_with_mention = room_with_mention.memberships.find_by(user: @david)
    membership_with_mention.update!(unread_at: 1.hour.ago)

    # Room without mention (just a regular unread message)
    room_without_mention = rooms(:watercooler)
    room_without_mention.messages.create!(body: "Regular message", creator: @jason)
    membership_without_mention = room_without_mention.memberships.find_by(user: @david)
    membership_without_mention.update!(unread_at: 1.hour.ago)

    # Visit activity page to set session timestamp
    get activity_inbox_url

    # Clear only activity
    post clear_inbox_url, params: { scope: "activity" }

    membership_with_mention.reload
    membership_without_mention.reload

    assert membership_with_mention.read?, "Room with mention should be marked as read"
    assert membership_without_mention.unread?, "Room without mention should remain unread"
  end

  test "clear with scope direct_messages only clears DM rooms" do
    # DM room
    dm_room = rooms(:david_and_jason)
    dm_membership = dm_room.memberships.find_by(user: @david)
    dm_membership.update!(unread_at: 1.hour.ago)

    # Regular room with mention
    room_with_mention = rooms(:pets)
    room_with_mention.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason
    )
    membership_with_mention = room_with_mention.memberships.find_by(user: @david)
    membership_with_mention.update!(unread_at: 1.hour.ago)

    # Visit direct_messages page to set session timestamp
    get direct_messages_inbox_url

    # Clear only direct_messages
    post clear_inbox_url, params: { scope: "direct_messages" }

    dm_membership.reload
    membership_with_mention.reload

    assert dm_membership.read?, "DM room should be marked as read"
    assert membership_with_mention.unread?, "Room with mention should remain unread"
  end

  # ===================
  # Pagination tests
  # ===================

  # ===================
  # Broadcast removal tests
  # ===================

  test "soft-deleting a message broadcasts removal for its notifications" do
    room = rooms(:pets)
    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "broadcast_removal_test"
    )

    notification = Notification.find_by(user: @david, message: message)
    assert notification

    message.deactivate!

    assert_rendered_turbo_stream_broadcast @david, :inbox_activity,
      action: "remove",
      target: notification
  end

  test "deactivating a room removes its notifications from activity" do
    room = rooms(:pets)
    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} room deactivation test</div>",
      creator: @jason,
      client_message_id: "room_deactivate_activity"
    )

    get activity_inbox_url
    assert_match "room deactivation test", response.body

    room.deactivate

    get activity_inbox_url
    assert_no_match "room deactivation test", response.body
  end

  test "editing a mention out of a message removes notification from activity" do
    room = rooms(:pets)
    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} edit removal test</div>",
      creator: @jason,
      client_message_id: "edit_removal_activity"
    )

    get activity_inbox_url
    assert_match "edit removal test", response.body

    message.update!(body: "<div>Hey everyone</div>")

    get activity_inbox_url
    assert_no_match "edit removal test", response.body
  end

  test "destroying a boost broadcasts removal for its notification" do
    room = rooms(:pets)
    message = room.messages.create!(
      body: "Boost removal broadcast",
      creator: @david,
      client_message_id: "boost_removal_broadcast"
    )

    boost = message.boosts.create!(content: "🔥", booster: @jason)
    notification = Notification.find_by(boost_id: boost.id)
    assert notification

    boost.destroy!

    assert_rendered_turbo_stream_broadcast @david, :inbox_activity,
      action: "remove",
      target: notification
  end

  # ===================
  # Pagination tests
  # ===================

  test "activity supports before pagination" do
    room = rooms(:pets)

    3.times do |i|
      room.messages.create!(
        body: "<div>Hey #{mention_attachment_for(:david)}</div>",
        creator: @jason,
        client_message_id: "paginate_before_#{i}"
      )
    end

    last_notification = Notification.where(user: @david, activity_type: "mention").order(:created_at).last
    get activity_inbox_url, params: { before: last_notification.id }
    assert_response :success
  end

  test "activity supports after pagination" do
    room = rooms(:pets)

    3.times do |i|
      room.messages.create!(
        body: "<div>Hey #{mention_attachment_for(:david)}</div>",
        creator: @jason,
        client_message_id: "paginate_after_#{i}"
      )
    end

    first_notification = Notification.where(user: @david, activity_type: "mention").order(:created_at).first
    get activity_inbox_url, params: { after: first_notification.id }
    assert_response :success
  end
end
