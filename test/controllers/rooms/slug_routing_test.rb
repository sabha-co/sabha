require "test_helper"

class Rooms::SlugRoutingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @room = rooms(:hq)
    @room.update!(slug: "headquarters")
  end

  test "room accessible via slug" do
    get "/headquarters"
    assert_response :success
  end

  test "room accessible via numeric id redirects to slug" do
    get room_url(@room)
    assert_redirected_to room_slug_url(@room.slug)
  end

  test "room without slug uses numeric id" do
    @room.update!(slug: nil)
    get room_url(@room)
    assert_response :success
  end

  test "slug with query params preserved on redirect" do
    get room_url(@room) + "?foo=bar"
    assert_redirected_to room_slug_url(@room.slug) + "?foo=bar"
  end

  test "viewing specific message does not redirect to slug" do
    message = @room.messages.create!(body: "Test", creator: users(:david))
    get room_url(@room, message_id: message.id)
    assert_response :success
  end

  test "non-member cannot access room via slug" do
    sign_in :rachel # User not in the room

    get "/headquarters"
    # Should redirect with alert
    assert_redirected_to root_url
    assert_equal "Room not found or inaccessible", flash[:alert]
  end

  test "room constraint checks for active rooms only" do
    # First verify the room is accessible
    get "/headquarters"
    assert_response :success

    # Now deactivate and verify it's not found via slug constraint
    @room.update!(active: false)

    # The constraint will fail, so the route won't match
    # This results in a routing error which Rails handles
    assert_raises ActionController::RoutingError do
      get "/headquarters"
    end
  end
end
