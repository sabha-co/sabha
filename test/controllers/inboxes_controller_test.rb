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

  test "activity includes direct messages from other users" do
    dm_room = rooms(:david_and_jason)
    dm_message = dm_room.messages.create!(
      body: "Hey David direct message!",
      creator: @jason,
      client_message_id: "dm_test_1"
    )

    get activity_inbox_url
    assert_response :success
    assert_match "Hey David direct message!", response.body
  end

  test "mentioning a non-member adds them to the room so they can see the mention" do
    # Kevin is not initially a member of pets room
    sign_in :kevin
    kevin = users(:kevin)
    room = rooms(:pets)

    assert_not room.users.include?(kevin), "Kevin should not be a member of pets initially"

    # Creating a message that mentions kevin automatically involves him in the room
    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)} you can see this because mentioning adds you</div>",
      creator: @jason,
      client_message_id: "auto_involve_test"
    )

    room.reload
    assert room.users.include?(kevin), "Kevin should now be a member of pets after being mentioned"

    get activity_inbox_url
    assert_response :success
    # Kevin CAN see the mention because he was auto-added to the room
    assert_match "you can see this because mentioning adds you", response.body
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

  test "bookmarks excludes inactive bookmarks" do
    message = messages(:first)
    message.update!(body: "Inactive bookmark marker")
    bookmark = Bookmark.create!(user: @david, message: message)
    bookmark.update!(active: false)

    get bookmarks_inbox_url
    assert_response :success
    assert_no_match "Inactive bookmark marker", response.body
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

  # ===================
  # Pagination tests
  # ===================

  test "activity supports before pagination" do
    room = rooms(:pets)

    messages = 3.times.map do |i|
      room.messages.create!(
        body: "<div>Hey #{mention_attachment_for(:david)}</div>",
        creator: @jason,
        client_message_id: "paginate_before_#{i}"
      )
    end

    get activity_inbox_url, params: { before: messages.last.id }
    assert_response :success
  end

  test "activity supports after pagination" do
    room = rooms(:pets)

    messages = 3.times.map do |i|
      room.messages.create!(
        body: "<div>Hey #{mention_attachment_for(:david)}</div>",
        creator: @jason,
        client_message_id: "paginate_after_#{i}"
      )
    end

    get activity_inbox_url, params: { after: messages.first.id }
    assert_response :success
  end
end
