require "test_helper"

class Messages::BookmarksControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    sign_in :david
    @david = users(:david)
    @message = messages(:first)
  end

  # ===================
  # Create action tests
  # ===================

  test "create creates bookmark for current user" do
    assert_difference -> { Bookmark.count }, 1 do
      post message_bookmarks_url(@message), as: :turbo_stream
    end

    bookmark = Bookmark.last
    assert_equal @david, bookmark.user
    assert_equal @message, bookmark.message
    assert bookmark.active?
  end

  test "create is idempotent - does not create duplicate" do
    Bookmark.create!(user: @david, message: @message)

    assert_no_difference -> { Bookmark.count } do
      post message_bookmarks_url(@message), as: :turbo_stream
    end
  end

  test "create returns turbo stream response" do
    post message_bookmarks_url(@message), as: :turbo_stream
    assert_response :success
    assert_match "turbo-stream", response.content_type
  end

  test "create requires message to be reachable" do
    # Create a message in a room david is not a member of
    closed_room = Rooms::Closed.create!(name: "Secret", creator: users(:jason))
    closed_room.memberships.grant_to(users(:jason))
    secret_message = closed_room.messages.create!(
      body: "Secret",
      creator: users(:jason),
      client_message_id: "secret_1"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      post message_bookmarks_url(secret_message), as: :turbo_stream
    end
  end

  # ===================
  # Destroy action tests
  # ===================

  test "destroy soft deletes bookmark" do
    bookmark = Bookmark.create!(user: @david, message: @message)

    assert_no_difference -> { Bookmark.count } do
      delete message_bookmarks_url(@message), as: :turbo_stream
    end

    bookmark.reload
    assert_not bookmark.active?, "Bookmark should be deactivated"
  end

  test "destroy only affects current user bookmark" do
    jason_bookmark = Bookmark.create!(user: users(:jason), message: @message)
    david_bookmark = Bookmark.create!(user: @david, message: @message)

    delete message_bookmarks_url(@message), as: :turbo_stream

    jason_bookmark.reload
    david_bookmark.reload

    assert jason_bookmark.active?, "Other user's bookmark should remain active"
    assert_not david_bookmark.active?, "Current user's bookmark should be deactivated"
  end

  test "destroy handles non-existent bookmark gracefully" do
    # No bookmark exists
    assert_nothing_raised do
      delete message_bookmarks_url(@message), as: :turbo_stream
    end
    assert_response :success
  end

  test "destroy returns turbo stream response" do
    Bookmark.create!(user: @david, message: @message)

    delete message_bookmarks_url(@message), as: :turbo_stream
    assert_response :success
    assert_match "turbo-stream", response.content_type
  end

  test "destroy requires message to be reachable" do
    closed_room = Rooms::Closed.create!(name: "Secret", creator: users(:jason))
    closed_room.memberships.grant_to(users(:jason))
    secret_message = closed_room.messages.create!(
      body: "Secret",
      creator: users(:jason),
      client_message_id: "secret_destroy_1"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      delete message_bookmarks_url(secret_message), as: :turbo_stream
    end
  end

  # ===================
  # Integration tests
  # ===================

  test "bookmark toggle workflow" do
    # Initially no bookmark
    assert_nil Bookmark.find_by(user: @david, message: @message)

    # Create bookmark
    post message_bookmarks_url(@message), as: :turbo_stream
    bookmark = Bookmark.find_by(user: @david, message: @message)
    assert bookmark.active?

    # Remove bookmark
    delete message_bookmarks_url(@message), as: :turbo_stream
    bookmark.reload
    assert_not bookmark.active?
  end
end
