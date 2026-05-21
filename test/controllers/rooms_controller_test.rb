require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index redirects to the user's last room" do
    get rooms_url
    assert_redirected_to room_url(users(:david).rooms.last)
  end

  test "show" do
    get room_url(users(:david).rooms.last)
    assert_response :success
  end

  test "shows records the last room visited in a cookie" do
    get room_url(users(:david).rooms.last)
    assert response.cookies[:last_room] = users(:david).rooms.last.id
  end

  test "destroy" do
    # 2 broadcasts: one for :starred_rooms and one for :shared_rooms
    assert_turbo_stream_broadcasts [ accounts(:signal), :rooms ], count: 2 do
      assert_difference -> { Room.active.count }, -1 do
        delete room_url(rooms(:designers))
      end
    end
  end

  test "destroy redirects with alert for original room" do
    assert_no_difference -> { Room.active.count } do
      delete room_url(rooms(:hq))
    end

    assert_equal "The original room can't be deleted", flash[:alert]
  end

  test "show redirects thread rooms to parent room" do
    parent_message = rooms(:pets).messages.create!(
      body: "Thread parent",
      creator: users(:jason),
      client_message_id: "redirect_thread_1"
    )
    thread = Rooms::Thread.create_for(
      { parent_message_id: parent_message.id, creator: users(:jason) },
      users: [ users(:david), users(:jason) ]
    )

    get room_url(thread)
    assert_redirected_to room_at_message_url(parent_message.room, parent_message)
  end

  test "index skips thread rooms" do
    parent_message = rooms(:pets).messages.create!(
      body: "Thread parent for index",
      creator: users(:jason),
      client_message_id: "index_thread_1"
    )
    Rooms::Thread.create_for(
      { parent_message_id: parent_message.id, creator: users(:jason) },
      users: [ users(:david) ]
    )

    get rooms_url
    # Should redirect to a non-thread room, not the thread
    assert_redirected_to room_url(users(:david).rooms.without_threads.last)
  end

  test "DM back button links to referrer when coming from activity" do
    dm_room = rooms(:david_and_jason)

    get room_url(dm_room), headers: { "HTTP_REFERER" => inbox_activity_index_url }
    assert_response :success
    assert_select "a[href='#{inbox_activity_index_path}']"
  end

  test "DM back button defaults to DM inbox without referrer" do
    dm_room = rooms(:david_and_jason)

    get room_url(dm_room)
    assert_response :success
    assert_select "a[href='#{inbox_direct_messages_path}']"
  end

  test "DM back button prefers from param over referrer" do
    dm_room = rooms(:david_and_jason)

    get room_url(dm_room, from: inbox_threads_path), headers: { "HTTP_REFERER" => inbox_activity_index_url }
    assert_response :success
    assert_select "a[href='#{inbox_threads_path}']"
  end

  test "back button ignores non-inbox referrers for DMs" do
    dm_room = rooms(:david_and_jason)

    get room_url(dm_room), headers: { "HTTP_REFERER" => room_url(rooms(:hq)) }
    assert_response :success
    assert_select "a[href='#{inbox_direct_messages_path}']"
  end

  test "back button preserves search query string from referrer" do
    dm_room = rooms(:david_and_jason)

    get room_url(dm_room), headers: { "HTTP_REFERER" => "http://www.example.com/searches?q=hello" }
    assert_response :success
    assert_select "a[href='/searches?q=hello']"
  end

  test "destroy only allowed for creators or those who can administer" do
    sign_in :jz

    assert_no_difference -> { Room.active.count } do
      delete room_url(rooms(:designers))
      assert_response :forbidden
    end

    rooms(:designers).update! creator: users(:jz)

    assert_difference -> { Room.active.count }, -1 do
      delete room_url(rooms(:designers))
    end
  end
end
