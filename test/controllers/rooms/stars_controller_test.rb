require "test_helper"

class Rooms::StarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create stars a room" do
    membership = memberships(:david_designers)
    assert_not membership.starred?

    post room_star_url(rooms(:designers))
    assert membership.reload.starred?
  end

  test "destroy unstars a room" do
    membership = memberships(:david_watercooler)
    assert membership.starred?

    delete room_star_url(rooms(:watercooler))
    assert_not membership.reload.starred?
  end

  test "create broadcasts remove from old section and append to new" do
    room = rooms(:designers)

    # 1 remove (from shared_rooms) + 1 append (to starred_rooms) = 2
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 2 do
      post room_star_url(room)
    end

    assert_rendered_turbo_stream_broadcast users(:david), :rooms, action: "remove",
      target: [ room, "shared_rooms_list_node" ]
    assert_rendered_turbo_stream_broadcast users(:david), :rooms, action: "append", target: "starred_rooms" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(room, "starred_rooms_list_node")}" do
        assert_select ".room-menu button", text: "Remove from favorites", count: 1
      end
    end
  end

  test "destroy broadcasts remove from old section and append to new" do
    room = rooms(:watercooler)

    # 1 remove (from starred_rooms) + 1 append (to shared_rooms) = 2
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 2 do
      delete room_star_url(room)
    end

    assert_rendered_turbo_stream_broadcast users(:david), :rooms, action: "remove",
      target: [ room, "starred_rooms_list_node" ]
    assert_rendered_turbo_stream_broadcast users(:david), :rooms, action: "append", target: "shared_rooms" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(room, "shared_rooms_list_node")}" do
        assert_select ".room-menu button", text: "Add to favorites", count: 1
        assert_select ".room-menu button", text: "Remove from favorites", count: 0
      end
    end
  end

  test "cannot star a direct room" do
    post room_star_url(rooms(:david_and_jason))
    assert_response :unprocessable_entity
    assert_not memberships(:david_david_and_jason).reload.starred?
  end

  test "cannot star an invisible membership" do
    memberships(:david_designers).update!(involvement: :invisible)

    post room_star_url(rooms(:designers))
    assert_response :unprocessable_entity
    assert_not memberships(:david_designers).reload.starred?
  end
end
