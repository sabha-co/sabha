require "test_helper"

class Rooms::OpensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show redirects to get general show" do
    get rooms_open_url(users(:david).rooms.opens.last)
    assert_redirected_to room_url(users(:david).rooms.opens.last)
  end

  test "new renders the unified room form posting to rooms_opens" do
    get new_rooms_open_url

    assert_response :success
    assert_select "form[action=?]", rooms_opens_path
    assert_select "input[name='room[name]']"
  end

  test "create without auto_join redirects to room" do
    # 1 per-user broadcast to shared_rooms (new rooms are never starred)
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
      post rooms_opens_url, params: { room: { name: "My New Room" } }
    end

    assert_equal 1, Room.last.memberships.count
    assert_redirected_to room_url(Room.last)
  end

  test "create with auto_join adds all users and redirects to room" do
    post rooms_opens_url, params: { room: { name: "Forced Room", auto_join: true } }

    assert_equal User.count, Room.last.memberships.count
    assert Room.last.auto_join?
    assert_redirected_to room_url(Room.last)
  end

  test "create with auto_join persists flag so future users are auto-joined" do
    post rooms_opens_url, params: { room: { name: "Persistent Auto Room", auto_join: true } }
    room = Room.last

    new_user = User.create!(name: "Future User", email_address: "future@example.com", password: "secret123456")

    assert room.auto_join?, "Room should persist auto_join flag"
    assert room.memberships.exists?(user: new_user), "Future user should be auto-joined"
  end

  test "only admins or creators can update" do
    sign_in :jz

    assert_turbo_stream_broadcasts [ accounts(:signal), :rooms ], count: 0 do
      put rooms_open_url(rooms(:hq)), params: { room: { name: "New Name" } }
    end

    assert_response :forbidden
    assert_equal "HQ", rooms(:hq).reload.name, "name must not change on forbidden update"
  end

  test "update" do
    # Broadcasts happen via RoomUpdateBroadcastJob which is async
    put rooms_open_url(rooms(:pets)), params: { room: { name: "New Name" } }

    assert_redirected_to room_url(rooms(:pets))
    assert_equal "New Name", rooms(:pets).reload.name
  end

  test "update a closed room to be open does not auto-add all users" do
    original_count = rooms(:designers).memberships.count
    put rooms_open_url(rooms(:designers)), params: { room: { name: "Doesn't matter" } }
    assert_equal original_count, rooms(:designers).memberships.count
  end

  test "update a closed room to be open with auto_join adds all users" do
    put rooms_open_url(rooms(:designers)), params: { room: { name: "Doesn't matter", auto_join: true } }
    assert_equal User.count, rooms(:designers).memberships.count
  end

  test "non-admin cannot create room when restricted to administrators" do
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    # A stale/disabled "New room" link is a navigation, so it lands on the
    # styled, in-app 403 that explains the wall.
    get new_rooms_open_url
    assert_response :forbidden
    assert_select ".empty-state__title", text: "Administrators only"

    # The form post is not a navigation — it stays a bare status.
    post rooms_opens_url, params: { room: { name: "My New Room" } }
    assert_response :forbidden
    assert_select ".empty-state__title", count: 0
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

  # Event messages

  test "update posts rename event when name changes" do
    room = rooms(:pets)

    assert_difference -> { Message.unscoped.where(room: room, event: "room_renamed").count } do
      put rooms_open_url(room), params: { room: { name: "New Pets Name" } }
    end

    event = Message.unscoped.where(room: room, event: "room_renamed").last
    assert_equal "renamed the room from All Pets to New Pets Name", event.reload.plain_text_body
  end

  test "update does not post rename event when name unchanged" do
    room = rooms(:pets)

    assert_no_difference -> { Message.unscoped.where(room: room, event: "room_renamed").count } do
      put rooms_open_url(room), params: { room: { name: room.name } }
    end
  end

  # Tabbed edit layout

  test "edit renders tabbed layout with three tabs" do
    get edit_rooms_open_url(rooms(:pets))
    assert_response :success
    assert_select '[role="tablist"]', 1
    assert_select '[role="tab"]', 3
    assert_select '[role="tabpanel"]', 3
    assert_select '[role="tab"]', text: /About/
    assert_select '[role="tab"]', text: /Members/
    assert_select '[role="tab"]', text: /Settings/
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

  # Only open and closed rooms are in reach here. Every case below is a room its
  # creator administers, so the permission check passes and the room type is the
  # only thing standing between a private conversation and the whole account.

  test "a direct room can't be promoted to an open room by a participant" do
    sign_in :kevin
    direct = Rooms::Direct.create_for({ creator: users(:kevin) }, users: [ users(:kevin), users(:jz) ])

    put rooms_open_url(direct), params: { room: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Direct", Room.find(direct.id).type
    assert_not Room.browsable_by(users(:rachel)).exists?(id: direct.id)
  end

  test "a direct room can't be promoted to an open room by an administrator" do
    put rooms_open_url(rooms(:david_and_kevin)), params: { room: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Direct", Room.find(rooms(:david_and_kevin).id).type
  end

  test "a chat thread can't be promoted out of its closed room into an open one" do
    sign_in :kevin
    message = rooms(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Rooms::Thread.find_or_create_for(message, creator: users(:kevin))

    put rooms_open_url(thread), params: { room: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Thread", Room.find(thread.id).type
    assert_not Room.browsable_by(users(:rachel)).exists?(id: thread.id)
  end

  test "a forum can't be converted into an open room" do
    put rooms_open_url(rooms(:help_desk)), params: { room: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Rooms::Forum", Room.find(rooms(:help_desk).id).type
  end
end
