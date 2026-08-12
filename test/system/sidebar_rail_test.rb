require "application_system_test_case"

# The tablet-width rail (834-1279px): collapsed to icons, the toggle expands
# the full sidebar over the conversation, and pointing outside or navigating
# closes it again.
class SidebarRailTest < ApplicationSystemTestCase
  RAIL = [ 1024, 768 ]
  DESKTOP = [ 1400, 1400 ] # keep in sync with the driver's window_size

  setup do
    sign_in "kevin@37signals.com"
    page.current_window.resize_to(*RAIL)
  end

  teardown do
    page.current_window.resize_to(*DESKTOP)
  end

  test "toggle expands the rail and an outside press collapses it" do
    assert_no_selector "#sidebar.open"

    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"

    page.driver.browser.mouse.click(x: 800, y: 400)
    assert_no_selector "#sidebar.open"
  end

  test "picking a room from the expanded rail navigates and collapses it" do
    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"

    click_on "Designers"

    assert_selector ".composer"
    assert_no_selector "#sidebar.open"
  end

  test "the closed rail previews the top rooms as compact glyph rows with names and section chrome hidden" do
    assert_no_selector "#sidebar.open"

    # The main Rooms list still renders its rows in the rail (they carry the
    # live unread badges), capped to a compact preview.
    assert_selector ".rail-rooms .room-row", minimum: 1
    assert_operator all(".rail-rooms .room-row", visible: true).size, :<=, 4

    # Names and section headers collapse away — the rail shows glyph + badge.
    assert_no_selector ".rail-rooms .room__name", visible: true
    assert_no_selector ".rooms .sidebar__label", visible: true
    assert_selector ".rail-rooms .room__glyph", visible: true

    # Expanding restores the full sidebar with names.
    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"
    assert_selector ".rail-rooms .room__name", visible: true
  end
end
