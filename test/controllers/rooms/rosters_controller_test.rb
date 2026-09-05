require "test_helper"

class Rooms::RostersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @room = rooms(:designers)
    @room.memberships.active.update_all(connections: 0, connected_at: nil)
  end

  test "room info keeps controls and sends member management to settings" do
    memberships(:jz_designers).update!(connections: 1, connected_at: 1.minute.ago)

    get room_roster_url(@room)

    assert_response :success
    assert_select "turbo-frame#thread_panel_frame"
    assert_select "a[href=?][data-turbo-frame='_top']", edit_rooms_closed_path(@room), text: /Settings/
    assert_select ".roster__notifications"
    assert_select ".roster__activity, .roster__disclosure, .roster__footer, .roster__meta", count: 0
    assert_select "turbo-frame#room_members, turbo-frame[data-turbo-frame-src]", count: 0
    assert_select "a, button", text: /Manage members|Leave room/, count: 0
    assert_no_match(/Here now|Recently here|All members|here now/, response.body)
  end

  test "offers a favourite toggle for a starrable room" do
    get room_roster_url(@room)

    assert_response :success
    assert_select "button.roster__fav[data-star-toggle-url-value=?]", room_star_path(@room)
  end

  test "omits the favourite toggle for a direct message" do
    get room_roster_url(rooms(:david_and_jason))

    assert_response :success
    assert_select "button.roster__fav", false
  end

  test "a non-member cannot see a room's roster" do
    sign_in :rachel

    assert_raises ActiveRecord::RecordNotFound do
      get room_roster_url(@room)
    end
  end
end
