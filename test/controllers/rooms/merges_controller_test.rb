require "test_helper"

class Rooms::MergesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "administrator can merge rooms" do
    source_room = rooms(:pets)
    target_room = rooms(:hq)

    post room_merges_url(source_room), params: { target_room_id: target_room.id }

    assert_redirected_to room_url(target_room)
    assert_not source_room.reload.active?
  end

  test "non-administrator cannot merge rooms" do
    sign_in :jz

    source_room = rooms(:pets)
    target_room = rooms(:hq)

    post room_merges_url(source_room), params: { target_room_id: target_room.id }

    assert_response :forbidden
    assert source_room.reload.active?
  end

  test "merge requires valid target room" do
    source_room = rooms(:pets)

    post room_merges_url(source_room), params: { target_room_id: nil }

    assert_redirected_to edit_room_path(source_room)
    assert_equal "Please select a destination room!", flash[:alert]
    assert source_room.reload.active?
  end

  test "merge requires active target room" do
    source_room = rooms(:pets)
    target_room = rooms(:hq)
    target_room.update!(active: false)

    post room_merges_url(source_room), params: { target_room_id: target_room.id }

    assert_redirected_to edit_room_path(source_room)
    assert_equal "Please select a destination room!", flash[:alert]
  end

  test "merge deactivates source room memberships" do
    source_room = rooms(:pets)
    target_room = rooms(:hq)
    source_membership_count = source_room.memberships.active.count

    assert source_membership_count > 0

    post room_merges_url(source_room), params: { target_room_id: target_room.id }

    assert_equal 0, source_room.memberships.active.count
  end

  test "merge moves messages to target room" do
    source_room = rooms(:pets)
    target_room = rooms(:hq)

    # Create a message in source room
    message = source_room.messages.create!(body: "Test message", creator: users(:david))

    post room_merges_url(source_room), params: { target_room_id: target_room.id }

    assert_equal target_room.id, message.reload.room_id
  end

  test "merge broadcasts removal to sidebar" do
    source_room = rooms(:pets)
    target_room = rooms(:hq)

    assert_turbo_stream_broadcasts :rooms, count: 2 do
      post room_merges_url(source_room), params: { target_room_id: target_room.id }
    end
  end

  test "only open rooms can be merged" do
    # Closed rooms cannot be source
    source_room = rooms(:watercooler) # closed room
    target_room = rooms(:hq)

    assert_raises ActiveRecord::RecordNotFound do
      post room_merges_url(source_room), params: { target_room_id: target_room.id }
    end
  end
end
