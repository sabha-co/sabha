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

  test "the unsupported generic edit route is absent" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rooms/#{rooms(:designers).id}/edit", method: :get)
    end
  end

  test "standard room header links member avatars to room info and keeps the panel icon" do
    room = rooms(:watercooler)

    get room_url(room)

    assert_response :success
    assert_select "body.room-header--pencil", count: 1
    assert_select "a.navbar-roster--avatars[href=?][data-turbo-frame='thread_panel_frame']", room_roster_path(room), count: 1 do
      assert_select ".navbar-member-avatars" do
        assert_select ".avatar", count: 4
        assert_select ".navbar-member-avatars__overflow", text: "+1"
      end
    end
    assert_select "a.navbar-roster[href=?] .icon--panel-right", room_roster_path(room), count: 1
    assert_select ".navbar-actions a", count: 2
    assert_select ".navbar-actions .icon--users", count: 0
  end

  test "standard room header shows its exact four members without an overflow badge" do
    room = rooms(:hq)
    member_names = %i[david jason jz kevin].map { |fixture| users(fixture).name }

    get room_url(room)

    assert_response :success
    assert_select ".navbar-member-avatars" do
      assert_select ".navbar-member-avatars__avatar", count: 4
      member_names.each do |member_name|
        assert_select ".navbar-member-avatars__avatar[title=?]", member_name, count: 1
      end
      assert_select ".navbar-member-avatars__overflow", count: 0
    end
  end

  test "native standard room header keeps compact member management without web actions" do
    room = rooms(:watercooler)

    get room_url(room), headers: { "HTTP_USER_AGENT" => "Sabha Hotwire Native" }

    assert_response :success
    assert_select "body.room-header--pencil", count: 0
    assert_select "a.navbar-members--native[href=?]", edit_rooms_closed_path(room, tab: "members"), text: room.active_member_count.to_s
    assert_select ".navbar-members--web", count: 0
    assert_select ".navbar-member-avatars", count: 0
    assert_select ".navbar-roster", count: 0
  end

  test "the app layout mounts the connection-lost banner, hidden until the socket drops" do
    get room_url(users(:david).rooms.last)

    assert_response :success
    assert_select ".connection-banner[data-controller=?]", "connection-status"
    assert_select ".connection-banner.connection-banner--visible", false
  end

  test "the lazy sidebar frame renders a cold-start skeleton until its rooms load" do
    get room_url(users(:david).rooms.last)

    assert_response :success
    assert_select "turbo-frame#user_sidebar[src] .sidebar-skeleton" do
      assert_select ".sidebar-skeleton__workspace", count: 1
      assert_select ".sidebar-skeleton__menu .sidebar-skeleton__row", count: 5
      assert_select ".sidebar-skeleton__rooms .sidebar-skeleton__row", count: 4
      assert_select ".sidebar-skeleton__footer", count: 1
    end
  end

  test "show renders the direct-message nav header" do
    room = rooms(:david_and_kevin)

    get room_url(room)

    assert_response :success
    assert_select "body.room-header--pencil", count: 0
    # The recipient titles the conversation, and the header links to the room's settings.
    assert_select ".navbar-dm h1.navbar-title a[href=?]", edit_rooms_direct_path(room), text: /#{users(:kevin).name}/
  end

  test "one-on-one DM header keeps View profile and shows no participants pill" do
    room = rooms(:david_and_kevin)

    get room_url(room)

    assert_response :success
    assert_select ".navbar-actions a", text: "View profile"
    assert_select ".navbar-actions a[href=?]", edit_rooms_direct_path(room), count: 0
    assert_select ".navbar-member-avatars", count: 0
  end

  test "group DM header shows an N-people pill to the participants panel and a plain name" do
    group = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:kevin) ])

    get room_url(group)

    assert_response :success
    assert_select ".navbar-dm h1.navbar-title a", false, "the group name is plain text, not a link"
    assert_select ".navbar-actions a[href=?]", edit_rooms_direct_path(group)
    assert_select ".navbar-actions", text: /\d+ people/
    assert_select ".navbar-member-avatars", count: 0
  end

  test "composer carries the @everyone confirm threshold, member count, and cap flag" do
    room = rooms(:pets)

    get room_url(room)

    assert_response :success
    assert_select "form#composer[data-composer-everyone-confirm-threshold-value=?]",
                  Rails.configuration.x.everyone_mention.confirm_threshold.to_s
    assert_select "form#composer[data-composer-everyone-member-count-value=?]", room.active_member_count.to_s
    assert_select "form#composer[data-composer-everyone-capped-value='false']"
    assert_select ".composer__everyone-confirm[hidden]"
  end

  test "composer flags the @everyone cap when the room is over the ceiling" do
    room = rooms(:pets)
    original = Rails.configuration.x.everyone_mention.ceiling
    Rails.configuration.x.everyone_mention.ceiling = 1

    get room_url(room)

    assert_select "form#composer[data-composer-everyone-capped-value='true']"
  ensure
    Rails.configuration.x.everyone_mention.ceiling = original
  end

  test "show renders the new-messages separator inside the first unread message" do
    room = rooms(:pets)
    room.messages.create!(creator: users(:jason), body: "Seen already", client_message_id: "separator_seen")
    first_unread = room.messages.create!(creator: users(:jason), body: "New to you", client_message_id: "separator_unread")
    rewind_unread_to room.memberships.find_by!(user: users(:david)), first_unread

    get room_url(room)

    assert_response :success
    assert_select "[data-message-id='#{first_unread.id}'] #unread_separator", count: 1
  end

  test "show renders no new-messages separator when the membership is read" do
    room = rooms(:pets)
    room.messages.create!(creator: users(:jason), body: "Nothing new", client_message_id: "separator_none")
    catch_up room.memberships.find_by!(user: users(:david))

    get room_url(room)

    assert_response :success
    assert_select "#unread_separator", count: 0
  end

  test "shows records the last room visited in a cookie" do
    get room_url(users(:david).rooms.last)
    assert_equal users(:david).rooms.last.id.to_s, response.cookies["last_room"]
  end

  test "destroy" do
    # 3 broadcasts: one per sidebar section (:starred_rooms, :shared_rooms, :forum_rooms)
    assert_turbo_stream_broadcasts [ accounts(:signal), :rooms ], count: 3 do
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
