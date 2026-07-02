require "test_helper"

class Rooms::BrowseControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "browse lists forums the user is not already in" do
    Rooms::Forum.create_for({ name: "Discoverable Forum", creator: users(:david) }, users: users(:david))

    get rooms_browse_url

    assert_response :success
    assert_select "#browsable_rooms strong", text: "Discoverable Forum"
  end

  test "a forum the user already belongs to is not listed" do
    Rooms::Forum.create_for({ name: "My Forum", creator: users(:kevin) }, users: users(:kevin))

    get rooms_browse_url

    assert_select "strong", text: "My Forum", count: 0
  end

  test "joining a browsable forum grants membership and lands on the gallery" do
    forum = Rooms::Forum.create_for({ name: "Joinable", creator: users(:david) }, users: users(:david))

    assert_difference -> { forum.memberships.count }, 1 do
      post room_membership_url(forum)
    end

    assert_includes forum.reload.users, users(:kevin)
    assert_redirected_to room_url(forum)
  end
end
