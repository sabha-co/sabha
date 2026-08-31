require "application_system_test_case"

# Pins the sidebar room-row ⋯ menu: hover/right-click open, and each action
# wired to real state — favorite moves the row between sections, mute flips the
# bell, mark-as-read clears the badge, leave removes the room.
class SidebarRowMenuTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    dismiss_pwa_install_prompt
    wait_for_sidebar_streams
  end

  test "hovering a room row reveals its menu; the menu opens anchored" do
    open_row_menu "Designers"

    assert_selector ".room-row__menu-btn[aria-expanded='true']"
  end

  test "right-clicking a room row opens the same menu" do
    row = find("#shared_rooms .room-row", text: "Designers")

    # The contextmenu binding lands at Stimulus connect; retry while JS boots
    # (same tolerance reveal_message_actions applies to the message bar).
    3.times do
      row.right_click
      break if has_selector?(".room-menu", visible: :visible, wait: 2)
    end

    assert_selector ".room-menu", visible: :visible
  end

  test "the menu favorites a room, moving it into the starred section" do
    assert_selector "#favorites_section[hidden]", visible: :all

    open_row_menu "Designers"
    click_on "Add to favorites"

    assert_selector "#starred_rooms .room-row", text: "Designers", wait: 10
    assert_no_selector "#shared_rooms .room-row", text: "Designers"
    assert_no_selector "#favorites_section[hidden]"
  end

  test "the menu mutes and the row shows the muted bell" do
    open_row_menu "Designers"
    click_on "Mute room"

    assert_selector "#shared_rooms .room-row .muted-indicator", wait: 10
  end

  test "the menu marks a room as read, clearing its badge" do
    # Not the landing room — arriving in a room clears its own unread state
    memberships(:kevin_designers).update!(marked_unread: true, unread_notifications_count: 2)
    visit root_path
    wait_for_sidebar_streams

    assert find("#shared_rooms .room-row", text: "Designers").has_selector?(".notification-badge", text: "2")

    open_row_menu "Designers"
    click_on "Mark as read"

    assert_no_selector "#shared_rooms .room-row .notification-badge", wait: 10
  end

  test "the menu leaves a room" do
    open_row_menu "Designers"
    click_on "Leave room"

    assert_no_selector ".room-row", text: "Designers", wait: 10
  end

  private
    def open_row_menu(room_name)
      row = find("#shared_rooms .room-row", text: room_name)
      row.hover
      row.find(".room-row__menu-btn").click
      assert_selector ".room-menu", visible: :visible
    end

    # The menu's effects arrive on the sidebar's :rooms stream, which can still
    # be subscribing when wait_for_cable_connection's first source connects —
    # a broadcast sent in that window is silently missed. Wait for every
    # source on the page instead.
    def wait_for_sidebar_streams
      find("#shared_rooms .room-row", match: :first)
      assert_no_selector "turbo-cable-stream-source:not([connected])", visible: :all
    end
end
