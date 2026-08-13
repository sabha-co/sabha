require "test_helper"

class Rooms::ClosedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show redirects to get general show" do
    get rooms_open_url(users(:david).rooms.closeds.last)
    assert_redirected_to room_url(users(:david).rooms.closeds.last)
  end

  test "new" do
    get new_rooms_closed_url
    assert_response :success
  end

  test "create" do
    # Only creator is added; 1 broadcast to the correct sidebar section
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
      post rooms_closeds_url, params: { room: { name: "My New Room" } }
    end

    new_room = Room.last
    assert_equal 1, new_room.memberships.count
    assert_redirected_to edit_rooms_closed_url(new_room, tab: "members")
  end

  test "update room name" do
    put rooms_closed_url(rooms(:designers)), params: { room: { name: "New Name" } }

    assert_redirected_to room_url(rooms(:designers))
    assert_equal "New Name", rooms(:designers).reload.name
  end

  test "only admins or creators can update" do
    sign_in :jz

    assert_turbo_stream_broadcasts [ accounts(:signal), :rooms ], count: 0 do
      put rooms_closed_url(rooms(:designers)), params: { room: { name: "New Name" } }
    end

    assert_response :forbidden
    assert rooms(:designers).reload.name, "Designers"
  end


  test "non-admin cannot create room when restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_rooms_closed_url
    assert_response :forbidden

    post rooms_closeds_url, params: { room: { name: "My New Room" } }
    assert_response :forbidden
  end

  test "admin can create room when restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_rooms_closed_url
    assert_response :success

    post rooms_closeds_url, params: { room: { name: "Admin Room" } }
    assert_redirected_to edit_rooms_closed_url(Room.last, tab: "members")
  end

  # Event messages

  test "update posts rename event when name changes" do
    room = rooms(:designers)

    assert_difference -> { Message.unscoped.where(room: room, event: "room_renamed").count } do
      put rooms_closed_url(room), params: { room: { name: "New Designers" } }
    end

    event = Message.unscoped.where(room: room, event: "room_renamed").last
    assert_equal "renamed the room from Designers to New Designers", event.reload.plain_text_body
  end

  test "update does not post events when nothing changes" do
    room = rooms(:designers)

    assert_no_difference -> { Message.unscoped.where(room: room).where.not(event: nil).count } do
      put rooms_closed_url(room), params: { room: { name: room.name } }
    end
  end

  # Destroy permission tests

  test "admin can destroy any closed room" do
    sign_in :david

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_closed_url(rooms(:designers))
    end

    assert_redirected_to root_url
  end

  test "creator can destroy their own closed room" do
    sign_in :kevin
    post rooms_closeds_url, params: { room: { name: "Kevin's Private Room" } }
    room = Room.last

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_closed_url(room)
    end

    assert_redirected_to root_url
  end

  test "non-admin non-creator cannot destroy closed room" do
    sign_in :jz

    assert_no_difference -> { Room.active.count } do
      delete rooms_closed_url(rooms(:designers))
    end

    assert_response :forbidden
  end

  # Tabbed edit layout

  test "edit renders the two-tab settings layout inside the shell" do
    get edit_rooms_closed_url(rooms(:designers))
    assert_response :success
    assert_select ".navbar-title", text: "Room settings"
    assert_select '[role="tablist"]', 1
    assert_select '[role="tab"]', 2
    assert_select '[role="tabpanel"]', 2
    assert_select '[role="tab"]', text: /Settings/
    assert_select '[role="tab"]', text: /Members/
    # A closed room's auto-join row renders disabled — opening the room enables it
    assert_select "#tab-settings .setting-row__title", text: "Open to everyone"
    assert_select "#tab-settings .setting-row--disabled .setting-row__title", text: "Add new members automatically"
  end

  # Creator update permission tests

  test "creator can update their own closed room" do
    sign_in :kevin
    post rooms_closeds_url, params: { room: { name: "Kevin's Room" } }
    room = Room.last

    put rooms_closed_url(room), params: { room: { name: "Kevin's Updated Room" } }

    assert_redirected_to room_url(room)
    assert_equal "Kevin's Updated Room", room.reload.name
  end

  test "a direct room can't be converted into a closed room" do
    sign_in :kevin
    direct = Rooms::Direct.create_for({ creator: users(:kevin) }, users: [ users(:kevin), users(:jz) ])

    put rooms_closed_url(direct), params: { room: { name: "Seized" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Direct", Room.find(direct.id).type
  end

  test "a chat thread can't be converted into a closed room" do
    sign_in :kevin
    message = rooms(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Rooms::Thread.find_or_create_for(message, creator: users(:kevin))

    put rooms_closed_url(thread), params: { room: { name: "Seized" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Thread", Room.find(thread.id).type
  end
end
