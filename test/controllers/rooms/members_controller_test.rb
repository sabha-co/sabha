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
