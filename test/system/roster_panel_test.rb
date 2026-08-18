require "application_system_test_case"

# Wide screens dock the room roster panel by default. Closing it is a sticky
# per-browser choice — rooms stay panel-free until the reader reopens it from
# the header, which clears the choice again.
class RosterPanelTest < ApplicationSystemTestCase
  setup do
    page.current_window.resize_to(1400, 1400)
    sign_in "kevin@37signals.com"
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "the docked roster responds to resizing and explicit dismissal" do
    join_room rooms(:designers)

    assert_selector "#thread-panel .roster", wait: 5

    # Narrowing into overlay territory tears down the ambient roster without
    # recording a dismissal, so it can dock again on a later wide navigation.
    page.current_window.resize_to(1000, 900)
    assert_no_selector "#thread-panel .roster"
    assert_nil page.evaluate_script("localStorage.getItem('thread-panel:roster-dismissed')")

    page.current_window.resize_to(1400, 1400)
    visit room_url(rooms(:hq))
    wait_for_network_idle!
    assert_selector "#thread-panel .roster", wait: 5

    find(".thread-panel__close").click
    assert_no_selector "#thread-panel .roster"

    visit room_url(rooms(:designers))
    wait_for_network_idle!
    assert_no_selector "#thread-panel .roster"

    find("a[href$='/roster']").click
    assert_selector "#thread-panel .roster", wait: 5

    visit room_url(rooms(:hq))
    wait_for_network_idle!
    assert_selector "#thread-panel .roster", wait: 5
  end
end
