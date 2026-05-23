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
      post message_bookmark_url(@message), as: :turbo_stream
    end

    bookmark = Bookmark.last
    assert_equal @david, bookmark.user
    assert_equal @message, bookmark.message
  end

  test "create is idempotent - does not create duplicate" do
    Bookmark.create!(user: @david, message: @message)

    assert_no_difference -> { Bookmark.count } do
      post message_bookmark_url(@message), as: :turbo_stream
    end
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
      post message_bookmark_url(secret_message), as: :turbo_stream
    end
  end

  # ===================
  # Destroy action tests
  # ===================

  test "destroy deletes bookmark" do
    Bookmark.create!(user: @david, message: @message)

    assert_difference -> { Bookmark.count }, -1 do
      delete message_bookmark_url(@message), as: :turbo_stream
    end
  end

  test "destroy only affects current user bookmark" do
    jason_bookmark = Bookmark.create!(user: users(:jason), message: @message)
    Bookmark.create!(user: @david, message: @message)

    assert_difference -> { Bookmark.count }, -1 do
      delete message_bookmark_url(@message), as: :turbo_stream
    end

    assert Bookmark.exists?(jason_bookmark.id), "Other user's bookmark should still exist"
  end

  test "destroy handles non-existent bookmark gracefully" do
    # No bookmark exists for current user — controller uses `&.destroy!` and no-ops.
    assert_no_difference -> { Bookmark.count } do
      delete message_bookmark_url(@message), as: :turbo_stream
    end
    assert_response :success
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
      delete message_bookmark_url(secret_message), as: :turbo_stream
    end
  end
end
