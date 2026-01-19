require "test_helper"

class Rooms::OpensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show redirects to get general show" do
    get rooms_open_url(users(:david).rooms.opens.last)
    assert_redirected_to room_url(users(:david).rooms.opens.last)
  end

  test "new" do
    get new_rooms_open_url
    assert_response :success
  end

  test "create" do
    # 2 broadcasts: one for :starred_rooms and one for :shared_rooms
    assert_turbo_stream_broadcasts :rooms, count: 2 do
      post rooms_opens_url, params: { room: { name: "My New Room" } }
    end

    assert_equal Room.last.memberships.count, User.count
    assert_redirected_to room_url(Room.last)
  end

  test "only admins or creators can update" do
    sign_in :jz

    assert_turbo_stream_broadcasts :rooms, count: 0 do
      put rooms_open_url(rooms(:hq)), params: { room: { name: "New Name" } }
    end

    assert_response :forbidden
    assert rooms(:hq).reload.name, "HQ"
  end

  test "update" do
    # Broadcasts happen via RoomUpdateBroadcastJob which is async
    put rooms_open_url(rooms(:pets)), params: { room: { name: "New Name" } }

    assert_redirected_to room_url(rooms(:pets))
    assert rooms(:pets).reload.name, "New Name"
  end

  test "update a closed room to be open" do
    put rooms_open_url(rooms(:designers)), params: { room: { name: "Doesn't matter" } }
    assert_equal rooms(:designers).memberships.count, User.count
  end

  test "non-admin cannot create room when restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_rooms_open_url
    assert_response :forbidden

    post rooms_opens_url, params: { room: { name: "My New Room" } }
    assert_response :forbidden
  end

  test "admin can create room when restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_rooms_open_url
    assert_response :success

    post rooms_opens_url, params: { room: { name: "Admin Room" } }
    assert_redirected_to room_url(Room.last)
  end

  # Destroy permission tests

  test "admin can destroy any room" do
    sign_in :david

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_open_url(rooms(:pets))
    end

    assert_redirected_to root_url
  end

  test "creator can destroy their own room" do
    # Create a room as non-admin
    sign_in :kevin
    post rooms_opens_url, params: { room: { name: "Kevin's Room" } }
    room = Room.last

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_open_url(room)
    end

    assert_redirected_to root_url
  end

  test "non-admin non-creator cannot destroy room" do
    sign_in :kevin

    assert_no_difference -> { Room.active.count } do
      delete rooms_open_url(rooms(:hq))
    end

    assert_response :forbidden
  end

  test "non-member cannot access room" do
    # Create a closed room without kevin
    sign_in :david
    post rooms_closeds_url, params: { room: { name: "Private Room" }, user_ids: [ users(:david).id ] }
    room = Room.last

    sign_in :kevin

    get room_url(room)
    assert_redirected_to root_url
  end

  # Creator update permission tests

  test "creator can update their own open room" do
    sign_in :kevin
    post rooms_opens_url, params: { room: { name: "Kevin's Room" } }
    room = Room.last

    put rooms_open_url(room), params: { room: { name: "Kevin's Updated Room" } }

    assert_redirected_to room_url(room)
    assert_equal "Kevin's Updated Room", room.reload.name
  end
end
