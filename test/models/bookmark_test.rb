require "test_helper"

class BookmarkTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @message = messages(:first)
  end

  # ===================
  # Basic association tests
  # ===================

  test "belongs to user" do
    bookmark = Bookmark.create!(user: @david, message: @message)
    assert_equal @david, bookmark.user
  end

  test "belongs to message" do
    bookmark = Bookmark.create!(user: @david, message: @message)
    assert_equal @message, bookmark.message
  end

  # ===================
  # Deactivatable concern tests
  # ===================

  test "includes Deactivatable concern" do
    bookmark = Bookmark.create!(user: @david, message: @message)
    assert bookmark.active?

    bookmark.deactivate!
    assert_not bookmark.active?

    bookmark.activate!
    assert bookmark.active?
  end

  test "active scope excludes inactive bookmarks" do
    bookmark = Bookmark.create!(user: @david, message: @message)
    assert_includes Bookmark.active, bookmark

    bookmark.deactivate!
    assert_not_includes Bookmark.active, bookmark
  end

  # ===================
  # with_bookmark_status tests
  # ===================

  test "with_bookmark_status sets bookmarked flag on bookmarked messages" do
    message1 = messages(:first)
    message2 = messages(:second)

    Bookmark.create!(user: @david, message: message1)
    # message2 is not bookmarked

    Current.user = @david
    messages = [ message1, message2 ]
    Bookmark.with_bookmark_status(messages)

    assert message1.bookmarked?, "Bookmarked message should have bookmarked=true"
    assert_not message2.bookmarked?, "Non-bookmarked message should have bookmarked=false"
  end

  test "with_bookmark_status handles empty messages array" do
    Current.user = @david
    result = Bookmark.with_bookmark_status([])
    assert_equal [], result
  end

  test "with_bookmark_status returns messages unchanged" do
    message = messages(:first)
    Bookmark.create!(user: @david, message: message)

    Current.user = @david
    messages = [ message ]
    result = Bookmark.with_bookmark_status(messages)

    assert_equal messages, result
  end

  test "with_bookmark_status only considers active bookmarks" do
    message = messages(:first)
    bookmark = Bookmark.create!(user: @david, message: message)
    bookmark.deactivate!

    Current.user = @david
    messages = [ message ]
    Bookmark.with_bookmark_status(messages)

    assert_not message.bookmarked?, "Message with inactive bookmark should have bookmarked=false"
  end

  test "with_bookmark_status only considers current user bookmarks" do
    message = messages(:first)
    Bookmark.create!(user: @jason, message: message)

    Current.user = @david
    messages = [ message ]
    Bookmark.with_bookmark_status(messages)

    assert_not message.bookmarked?, "Message bookmarked by another user should have bookmarked=false"
  end

  test "with_bookmark_status works with ActiveRecord::Relation" do
    message = messages(:first)
    Bookmark.create!(user: @david, message: message)

    Current.user = @david
    relation = Message.where(id: message.id)
    Bookmark.with_bookmark_status(relation)

    # Reload to check from relation
    loaded_message = relation.first
    assert loaded_message.bookmarked?
  end

  test "with_bookmark_status handles multiple messages efficiently" do
    # Create several messages and bookmark some
    room = rooms(:designers)
    messages_list = 5.times.map do |i|
      room.messages.create!(
        body: "Test message #{i}",
        creator: @jason,
        client_message_id: "populate_test_#{i}"
      )
    end

    # Bookmark first and third messages
    Bookmark.create!(user: @david, message: messages_list[0])
    Bookmark.create!(user: @david, message: messages_list[2])

    Current.user = @david
    Bookmark.with_bookmark_status(messages_list)

    assert messages_list[0].bookmarked?
    assert_not messages_list[1].bookmarked?
    assert messages_list[2].bookmarked?
    assert_not messages_list[3].bookmarked?
    assert_not messages_list[4].bookmarked?
  end

  # ===================
  # Ordered scope tests
  # ===================

  test "ordered scope orders by created_at" do
    message1 = messages(:first)
    message2 = messages(:second)

    bookmark2 = Bookmark.create!(user: @david, message: message2, created_at: 1.hour.ago)
    bookmark1 = Bookmark.create!(user: @david, message: message1, created_at: 2.hours.ago)

    ordered = Bookmark.where(user: @david).ordered
    assert_equal [ bookmark1, bookmark2 ], ordered.to_a
  end
end
