require "test_helper"

class Rooms::InvolvementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the involvement turbo frame for the room" do
    get room_involvement_url(rooms(:designers))

    assert_response :success
    assert_select "turbo-frame##{dom_id(rooms(:designers), :involvement)}"
  end

  test "update involvement sends turbo update when going invisible" do
    # When going invisible: 1 broadcast for sidebar section + 2 for removal + 1 for hidden_rooms append = 4
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 4 do
    assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "invisible" do
      put room_involvement_url(rooms(:watercooler)), params: { involvement: "invisible" }
      assert_redirected_to room_involvement_url(rooms(:watercooler))
    end
    end
  end

  test "update involvement sends turbo update when returning to visible" do
    # First make it invisible
    memberships(:david_watercooler).update!(involvement: "invisible")

    # When returning to visible: 1 broadcast for sidebar section + 1 for append + 1 for hidden_rooms removal = 3
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 3 do
    assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "invisible", to: "everything" do
      put room_involvement_url(rooms(:watercooler)), params: { involvement: "everything" }
      assert_redirected_to room_involvement_url(rooms(:watercooler))
    end
    end
  end

  test "updating involvement does not send extra turbo update when changing between visible states" do
    # 1 broadcast for the correct sidebar section (starred_rooms or shared_rooms)
    assert_turbo_stream_broadcasts [ users(:david), :rooms ], count: 1 do
    assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "mentions" do
      put room_involvement_url(rooms(:watercooler)), params: { involvement: "mentions" }
      assert_redirected_to room_involvement_url(rooms(:watercooler))
    end
    end
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
end
