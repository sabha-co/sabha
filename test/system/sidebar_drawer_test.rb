require "application_system_test_case"

# Protective coverage for the sidebar drawer on small screens: these
# behaviours must survive any shell restyling — the toggle opens the drawer,
# escape closes it and returns focus to the toggle, and picking a room
# navigates there and closes the drawer. Asserted through the stable
# #sidebar / .open / #sidebar-toggle contracts, not geometry.
class SidebarDrawerTest < ApplicationSystemTestCase
  MOBILE = [ 390, 844 ]
  DESKTOP = [ 1400, 1400 ] # keep in sync with the driver's window_size

  setup do
    sign_in "kevin@37signals.com"
    page.current_window.resize_to(*MOBILE)
  end

  teardown do
    page.current_window.resize_to(*DESKTOP)
  end

  test "toggle opens the drawer and escape closes it, returning focus" do
    assert_no_selector "#sidebar.open"

    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"

    find("body").send_keys :escape
    assert_no_selector "#sidebar.open"
    assert_equal "sidebar-toggle", page.evaluate_script("document.activeElement.id")
  end

  test "picking a room from the open drawer navigates and closes it" do
    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"

    click_on "Designers"

    assert_selector ".composer"
    assert_no_selector "#sidebar.open"
  end

  test "close button inside the drawer closes it" do
    find("#sidebar-toggle").click
    assert_selector "#sidebar.open"

    find(".sidebar__close").click
    assert_no_selector "#sidebar.open"
  end

  test "the closed drawer signals unread shared rooms and clears when they are read" do
    assert_selector "#shared_rooms .room", visible: :all, minimum: 1
    page.execute_script(<<~JS)
      document.querySelectorAll("#sidebar .unread, #sidebar .badge").forEach(row => row.classList.remove("unread", "badge"))
      document.querySelector("#shared_rooms .room").classList.add("unread")
    JS

    assert_equal '""', toggle_indicator_content

    page.execute_script('document.querySelector("#shared_rooms .room.unread").classList.remove("unread")')

    assert_equal "none", toggle_indicator_content
  end

  private
    def toggle_indicator_content
      page.evaluate_script('getComputedStyle(document.querySelector("#sidebar-toggle"), "::after").content')
    end
end
