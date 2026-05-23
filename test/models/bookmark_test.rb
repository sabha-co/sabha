require "test_helper"

class BookmarkTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @message = messages(:first)
  end

  # ===================
  # with_bookmark_status_for scope tests (LEFT JOIN approach)
  # ===================

  test "with_bookmark_status_for sets is_bookmarked via LEFT JOIN" do
    message1 = messages(:first)
    message2 = messages(:second)

    Bookmark.create!(user: @david, message: message1)
    # message2 is not bookmarked

    messages = Message.where(id: [ message1.id, message2.id ]).with_bookmark_status_for(@david)

    bookmarked_message = messages.find { |m| m.id == message1.id }
    unbookmarked_message = messages.find { |m| m.id == message2.id }

    assert bookmarked_message.bookmarked_by?(@david), "Bookmarked message should return true"
    assert_not unbookmarked_message.bookmarked_by?(@david), "Non-bookmarked message should return false"
  end

  test "with_bookmark_status_for correctly casts SQLite 0/1 to boolean" do
    message = messages(:first)
    # No bookmark exists

    messages = Message.where(id: message.id).with_bookmark_status_for(@david)
    loaded_message = messages.first

    # SQLite returns 0 for false, which is truthy in Ruby without proper casting
    assert_not loaded_message.bookmarked_by?(@david), "Unbookmarked message should return false, not truthy 0"
  end

  test "with_bookmark_status_for only considers specified user bookmarks" do
    message = messages(:first)
    Bookmark.create!(user: @jason, message: message)

    messages = Message.where(id: message.id).with_bookmark_status_for(@david)
    assert_not messages.first.bookmarked_by?(@david), "Message bookmarked by another user should return false"
  end

  test "with_bookmark_status_for handles multiple messages" do
    room = rooms(:designers)
    messages_list = 3.times.map do |i|
      room.messages.create!(body: "Test #{i}", creator: @jason, client_message_id: "scope_test_#{i}")
    end

    Bookmark.create!(user: @david, message: messages_list[0])
    Bookmark.create!(user: @david, message: messages_list[2])

    loaded = Message.where(id: messages_list.map(&:id)).with_bookmark_status_for(@david).index_by(&:id)

    assert loaded[messages_list[0].id].bookmarked_by?(@david)
    assert_not loaded[messages_list[1].id].bookmarked_by?(@david)
    assert loaded[messages_list[2].id].bookmarked_by?(@david)
  end

  # ===================
  # bookmarked_by? fallback tests
  # ===================

  test "bookmarked_by? falls back to query when scope not used" do
    message = messages(:first)
    Bookmark.create!(user: @david, message: message)

    # Load without scope - should fall back to exists? query
    loaded_message = Message.find(message.id)
    assert loaded_message.bookmarked_by?(@david)
    assert_not loaded_message.bookmarked_by?(@jason)
  end
end
