require "test_helper"

class Rooms::InvolvementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the involvement turbo frame for the room" do
    get room_involvement_url(rooms(:designers))

    assert_response :success
    assert_select "turbo-frame##{dom_id(rooms(:designers), :involvement)}"
    assert_select ".roster__notifications button[aria-expanded='false']"
    assert_select "button[role='menuitemradio']", count: 3
  end

  test "notification update returns and broadcasts the same dropdown" do
    room = rooms(:watercooler)
    patch room_involvement_url(room), params: { involvement: "mentions" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace'] template .roster__notifications"
    assert_select ".roster__notification-menu button[role='menuitemradio'][aria-checked='true']", text: "Mentions only"
    assert_rendered_turbo_stream_broadcast memberships(:david_watercooler), action: "replace", target: [ room, :involvement ] do
      assert_select "template .roster__notifications"
      assert_select ".roster__notification-menu button[role='menuitemradio'][aria-checked='true']", text: "Mentions only"
    end
  end

  test "update involvement sends turbo update when going invisible" do
    room = rooms(:watercooler)

    # When going invisible: 1 broadcast for sidebar section + 3 for removal (one
    # per sidebar section) + 1 for hidden_rooms append = 5
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 5 do
      assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "invisible" do
        put room_involvement_url(room), params: { involvement: "invisible" }
        assert_redirected_to room_involvement_url(room)
      end
    end

    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "replace", target: [ room, "shared_rooms_list_node" ]
    %w[starred_rooms shared_rooms forum_rooms].each do |list_name|
      assert_rendered_turbo_stream_broadcast users(:david), :rooms,
        action: "remove", target: [ room, "#{list_name}_list_node" ]
    end
    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "append", target: "hidden_rooms_list"
  end

  test "update involvement sends turbo update when returning to visible" do
    room = rooms(:watercooler)

    # First make it invisible
    memberships(:david_watercooler).update!(involvement: "invisible")

    # When returning to visible: 1 broadcast for sidebar section + 1 for append + 1 for hidden_rooms removal = 3
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 3 do
      assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "invisible", to: "everything" do
        put room_involvement_url(room), params: { involvement: "everything" }
        assert_redirected_to room_involvement_url(room)
      end
    end

    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "replace", target: [ room, "shared_rooms_list_node" ]
    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "remove", target: [ room, :hidden_room ]
    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "append", target: "shared_rooms"
  end

  test "updating involvement does not send extra turbo update when changing between visible states" do
    room = rooms(:watercooler)

    # 1 broadcast for the correct sidebar section (starred_rooms or shared_rooms)
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
      assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "mentions" do
        put room_involvement_url(room), params: { involvement: "mentions" }
        assert_redirected_to room_involvement_url(room)
      end
    end

    assert_rendered_turbo_stream_broadcast users(:david), :rooms,
      action: "replace", target: [ room, "starred_rooms_list_node" ]
  end

  test "updating involvement does not send extra turbo update for direct rooms" do
    # Direct rooms skip sidebar broadcasts entirely
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 0 do
      assert_changes -> { memberships(:david_david_and_jason).reload.involvement }, from: "everything", to: "nothing" do
        put room_involvement_url(rooms(:david_and_jason)), params: { involvement: "nothing" }
        assert_redirected_to room_involvement_url(rooms(:david_and_jason))
      end
    end
  end

  test "update honors a same-origin return_to" do
    put room_involvement_url(rooms(:watercooler)),
        params: { involvement: "mentions", return_to: "/rooms/#{rooms(:watercooler).id}" }

    assert_redirected_to "/rooms/#{rooms(:watercooler).id}"
  end

  test "update rejects a cross-origin return_to and falls back to the room involvement" do
    put room_involvement_url(rooms(:watercooler)),
        params: { involvement: "mentions", return_to: "https://evil.example.com/steal" }

    assert_redirected_to room_involvement_url(rooms(:watercooler))
  end
end
