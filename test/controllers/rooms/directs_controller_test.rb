require "test_helper"

class Rooms::DirectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create" do
    post rooms_directs_url, params: { user_ids: [ users(:jz).id ] }

    room = Room.last
    assert_redirected_to room_url(room)
    assert room.users.include?(users(:david))
    assert room.users.include?(users(:jz))
  end

  test "create only once per user set" do
    assert_difference -> { Room.all.count }, +1 do
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ] }
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ] }
    end
  end

  test "destroy only allowed for all room users" do
    sign_in :kevin

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_direct_url(rooms(:david_and_kevin))
      assert_redirected_to root_url
    end
  end

  test "non-admin cannot create DM when restricted to administrators" do
    accounts(:signal).settings.restrict_direct_messages_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_rooms_direct_url
    assert_response :forbidden

    post rooms_directs_url, params: { user_ids: [ users(:david).id ] }
    assert_response :forbidden
  end

  test "admin can create DM when restricted to administrators" do
    accounts(:signal).settings.restrict_direct_messages_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_rooms_direct_url
    assert_response :success

    post rooms_directs_url, params: { user_ids: [ users(:jz).id ] }
    assert_redirected_to room_url(Room.last)
  end
end
