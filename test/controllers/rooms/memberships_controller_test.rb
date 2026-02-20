require "test_helper"

class Rooms::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "joining an open room creates membership and redirects to room with notice" do
    room = rooms(:pets)
    room.memberships.where(user: users(:kevin)).update_all(active: false)

    assert_difference -> { Membership.where(room: room, user: users(:kevin), active: true).count } do
      post room_membership_url(room)
    end

    assert_redirected_to room_url(room)
    assert_equal "Joined #{room.name}", flash[:notice]
  end

  test "joining a closed room is forbidden" do
    Membership.where(room: rooms(:designers), user: users(:kevin)).update_all(active: false)

    post room_membership_url(rooms(:designers))
    assert_response :forbidden
  end

  test "leaving a room sets involvement to invisible" do
    sign_in :david
    room = rooms(:watercooler)

    delete room_membership_url(room)

    assert_redirected_to root_url
    assert_equal "You left #{room.name}", flash[:notice]
    assert memberships(:david_watercooler).reload.involved_in_invisible?
  end

  test "cannot leave a direct room" do
    sign_in :david

    delete room_membership_url(rooms(:david_and_jason))

    assert_redirected_to room_url(rooms(:david_and_jason))
    assert_equal "Cannot leave direct messages", flash[:alert]
  end
end
