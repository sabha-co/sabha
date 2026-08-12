require "test_helper"

class Rooms::BrowseControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "an auto-joined forum is not listed in Browse" do
    Rooms::Forum.create_for({ name: "Everyone Forum", creator: users(:david) }, users: users(:david))

    get rooms_browse_url

    assert_response :success
    assert_select ".list-row__title", text: "Everyone Forum", count: 0
  end

  test "a forum a member was removed from reappears in Browse so they can rejoin" do
    forum = Rooms::Forum.create_for({ name: "Discoverable Forum", creator: users(:david) }, users: users(:david))
    forum.remove_member!(users(:kevin), actor: users(:david))

    get rooms_browse_url

    assert_response :success
    assert_select "#browsable_rooms .list-row__title", text: "Discoverable Forum"
  end

  test "rejoining a browsable forum grants membership and lands on the gallery" do
    forum = Rooms::Forum.create_for({ name: "Joinable", creator: users(:david) }, users: users(:david))
    forum.remove_member!(users(:kevin), actor: users(:david))

    assert_difference -> { forum.memberships.count }, 1 do
      post room_membership_url(forum)
    end

    assert_includes forum.reload.users, users(:kevin)
    assert_redirected_to room_url(forum)
  end
end
