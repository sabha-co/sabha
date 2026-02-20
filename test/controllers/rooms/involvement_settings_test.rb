require "test_helper"

class Rooms::InvolvementSettingsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  # Mute toggle tests for shared rooms
  test "mute toggle on shared room sets involvement to nothing" do
    room = rooms(:hq)
    membership = memberships(:david_hq)
    assert membership.involved_in_everything?

    put room_involvement_url(room), params: { involvement: "nothing", return_to: edit_room_path(room) }

    assert membership.reload.involved_in_nothing?
  end

  test "unmute toggle on shared room sets involvement to mentions" do
    room = rooms(:hq)
    membership = memberships(:david_hq)
    membership.update!(involvement: "nothing")

    put room_involvement_url(room), params: { involvement: "mentions", return_to: edit_room_path(room) }

    assert membership.reload.involved_in_mentions?
  end

  # Mute toggle tests for direct rooms
  test "mute toggle on direct room sets involvement to nothing" do
    room = rooms(:david_and_jason)
    membership = memberships(:david_david_and_jason)
    assert membership.involved_in_everything?

    put room_involvement_url(room), params: { involvement: "nothing", return_to: edit_rooms_direct_path(room) }

    assert membership.reload.involved_in_nothing?
  end

  test "unmute toggle on direct room sets involvement to everything" do
    room = rooms(:david_and_jason)
    membership = memberships(:david_david_and_jason)
    membership.update!(involvement: "nothing")

    put room_involvement_url(room), params: { involvement: "everything", return_to: edit_rooms_direct_path(room) }

    assert membership.reload.involved_in_everything?
  end

  # Hide toggle tests for shared rooms
  test "hide toggle on shared room sets involvement to invisible" do
    room = rooms(:hq)
    membership = memberships(:david_hq)

    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 4 do
      put room_involvement_url(room), params: { involvement: "invisible", return_to: edit_room_path(room) }
    end

    assert membership.reload.involved_in_invisible?
  end

  test "unhide toggle on shared room sets involvement to mentions" do
    room = rooms(:hq)
    membership = memberships(:david_hq)
    membership.update!(involvement: "invisible")

    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 3 do
      put room_involvement_url(room), params: { involvement: "mentions", return_to: edit_room_path(room) }
    end

    assert membership.reload.involved_in_mentions?
  end

  # Return_to parameter tests
  test "returns to specified path after update" do
    room = rooms(:hq)

    put room_involvement_url(room), params: { involvement: "nothing", return_to: edit_room_path(room) }

    assert_redirected_to edit_room_path(room)
  end

  test "turbo stream request returns head ok" do
    room = rooms(:hq)

    put room_involvement_url(room), params: { involvement: "nothing" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
  end

  # Combined state tests
  test "muted and then hidden room is invisible" do
    room = rooms(:hq)
    membership = memberships(:david_hq)

    # First mute
    put room_involvement_url(room), params: { involvement: "nothing" }
    assert membership.reload.involved_in_nothing?

    # Then hide
    put room_involvement_url(room), params: { involvement: "invisible" }
    assert membership.reload.involved_in_invisible?
  end

  test "hidden room when unhidden returns to base involvement not nothing" do
    room = rooms(:hq)
    membership = memberships(:david_hq)

    # Hide the room
    membership.update!(involvement: "invisible")

    # Unhide should go to mentions (base for shared rooms), not nothing
    put room_involvement_url(room), params: { involvement: "mentions" }
    assert membership.reload.involved_in_mentions?
  end
end
