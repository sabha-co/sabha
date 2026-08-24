require "application_system_test_case"

# The search palette is the entry point for search: a layout-mounted scrim
# dialog opened by the keyboard shortcut and the sidebar row. Submitting (or
# picking a recent search) navigates to the results page — the palette itself
# never renders results. The composer's tools row deliberately carries no search
# button: it stays attach · emoji · send, and search belongs to ⌘K.
class SearchPaletteTest < ApplicationSystemTestCase
  setup { sign_in "david@37signals.com" }

  test "shortcut opens the palette and escape closes it" do
    find("body").send_keys [ :control, "k" ]

    assert_selector "#search_palette[open]"
    assert_selector ".search-palette__chip", text: "pizza"

    find(".search-palette__input").send_keys :escape

    assert_no_selector "#search_palette[open]"
  end

  test "sidebar search row opens the palette in place" do
    path_before = current_path

    find("#room-search").click

    assert_selector "#search_palette[open]"
    assert_equal path_before, current_path
  end

  test "submitting runs the search on the results page" do
    find("body").send_keys [ :control, "k" ]
    find(".search-palette__input").fill_in with: "pizza"
    find(".search-palette__input").send_keys :enter

    assert_selector ".searches__query", text: "pizza"
    assert_selector ".searches__bar .searches__input"
  end

  test "recent search chip runs that search" do
    find("body").send_keys [ :control, "k" ]

    within "#search_palette" do
      click_on "pizza"
    end

    assert_selector ".searches__query", text: "pizza"
  end
end
