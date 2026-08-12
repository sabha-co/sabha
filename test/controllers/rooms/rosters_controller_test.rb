require "test_helper"

class Rooms::RostersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @room = rooms(:designers)
    @room.memberships.active.update_all(connections: 0, connected_at: nil)
  end

  test "renders the roster in the thread-panel frame, grouping present members" do
    memberships(:jz_designers).update!(connections: 1, connected_at: 1.minute.ago)

    get room_roster_url(@room)

    assert_response :success
    assert_select "turbo-frame#thread_panel_frame"
    assert_select ".roster__label", text: /Here now/i
    assert_select ".roster__name", text: users(:jz).name
  end

  test "offers a link back to full settings" do
    get room_roster_url(@room)

    assert_response :success
    assert_select "a", text: /Settings/
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
