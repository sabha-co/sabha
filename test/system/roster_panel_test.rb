require "application_system_test_case"

# Wide screens dock the room roster panel by default. Closing it is a sticky
# per-browser choice — rooms stay panel-free until the reader reopens it from
# the header, which clears the choice again.
class RosterPanelTest < ApplicationSystemTestCase
  setup { sign_in "kevin@37signals.com" }

  test "a room opens with the roster docked, closing sticks, reopening unsticks" do
    join_room rooms(:designers)

    assert_selector "#thread-panel .roster", wait: 5

    find(".thread-panel__close").click
    assert_no_selector "#thread-panel .roster"

    visit room_url(rooms(:hq))
    wait_for_network_idle!
    assert_no_selector "#thread-panel .roster"

    find("a[href$='/roster']").click
    assert_selector "#thread-panel .roster", wait: 5

    visit room_url(rooms(:designers))
    wait_for_network_idle!
    assert_selector "#thread-panel .roster", wait: 5
  end
end
