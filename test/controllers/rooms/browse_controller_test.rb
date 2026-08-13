require "test_helper"

class Rooms::BrowseControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "browse lists every visible room with joined state" do
    get rooms_browse_url

    assert_response :success
    # Joined rooms show a quiet Joined chip and link into the room
    assert_select "#browsable_rooms .list-row", text: /HQ/ do
      assert_select ".browse-room__joined", text: "Joined"
      assert_select "a[href=?]", room_path(rooms(:hq))
    end
    # Un-joined open rooms keep the Join action
    Rooms::Open.create!(name: "Fresh Room", creator: users(:david))
    get rooms_browse_url
    assert_select "#browsable_rooms .list-row", text: /Fresh Room/ do
      assert_select "form[action=?]", room_membership_path(Room.find_by(name: "Fresh Room"))
    end
  end

  test "closed rooms appear only for their members" do
    get rooms_browse_url

    # Kevin belongs to designers but not watercooler
    assert_select "#browsable_rooms .list-row__title", text: rooms(:designers).name
    assert_select "#browsable_rooms .list-row__title", text: rooms(:watercooler).name, count: 0
  end

  test "an auto-joined forum is listed as joined in Browse" do
    Rooms::Forum.create_for({ name: "Everyone Forum", creator: users(:david) }, users: users(:david))

    get rooms_browse_url

    assert_response :success
    assert_select "#browsable_rooms .list-row", text: /Everyone Forum/ do
      assert_select ".browse-room__joined", text: "Joined"
    end
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
