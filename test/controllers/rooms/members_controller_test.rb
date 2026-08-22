require "test_helper"

class Rooms::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "add a member to a closed room" do
    room = rooms(:designers)

    assert_difference -> { room.reload.memberships.visible.count } do
      post room_members_url(room), params: { user_id: users(:bender).id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "add a member posts a joined event" do
    room = rooms(:designers)

    assert_difference -> { Message.unscoped.where(room: room, event: "member_joined").count } do
      post room_members_url(room), params: { user_id: users(:bender).id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "remove a member from a closed room" do
    room = rooms(:designers)

    assert_difference -> { room.reload.memberships.visible.count }, -1 do
      delete room_member_url(room, users(:jason)),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "remove a member posts a left event" do
    room = rooms(:designers)

    assert_difference -> { Message.unscoped.where(room: room, event: "member_left").count } do
      delete room_member_url(room, users(:jason)),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "cannot remove last visible member from a closed room" do
    room = rooms(:designers)
    visible = room.memberships.visible.to_a
    visible[1..].each { |m| m.update!(involvement: :invisible) }

    assert_no_difference -> { room.reload.memberships.visible.count } do
      delete room_member_url(room, visible.first.user),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :unprocessable_entity
  end

  test "index renders the roster with remove controls for an admin" do
    get room_members_url(rooms(:designers))

    assert_response :success
    assert_select "[data-member-id] button[data-action~='member-editor#remove']", minimum: 1
  end

  test "index roster has no remove controls for a non-admin" do
    sign_in :jz

    get room_members_url(rooms(:designers))

    assert_response :success
    assert_select "button[data-action~='member-editor#remove']", count: 0
  end

  test "search surfaces matching non-members to add" do
    get room_members_url(rooms(:designers), query: users(:rachel).name.split.first)

    assert_response :success
    assert_select "button[data-action~='member-editor#add']", text: /Add/
    assert_select "[data-member-id]", text: /#{users(:rachel).name}/
  end

  test "search surfaces matching members to remove" do
    get room_members_url(rooms(:designers), query: users(:jason).name)

    assert_response :success
    assert_select "[data-member-id=?] button[data-action~='member-editor#remove']", users(:jason).id
  end

  test "search does not offer to add for a non-admin" do
    sign_in :jz

    get room_members_url(rooms(:designers), query: users(:rachel).name.split.first)

    assert_response :success
    assert_select "button[data-action~='member-editor#add']", count: 0
  end

  test "non-admin cannot add members" do
    sign_in :jz

    post room_members_url(rooms(:designers)), params: { user_id: users(:bender).id },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :forbidden
  end

  test "non-admin cannot remove members" do
    sign_in :jz

    delete room_member_url(rooms(:designers), users(:jason)),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :forbidden
  end
end
