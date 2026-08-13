require "application_system_test_case"

# Desktop widths show the conversation rail beside the open DM; clicking a
# rail row swaps the conversation while the rail stays. Narrow widths keep
# today's behavior: the list is its own screen, the conversation full-width.
class DmSplitTest < ApplicationSystemTestCase
  setup { sign_in "david@37signals.com" }

  test "the rail swaps conversations in place at desktop width" do
    visit room_url(rooms(:david_and_kevin))

    assert_selector "#list-rail .dm-conversation", minimum: 2
    assert_selector ".navbar-title", text: "Kevin"

    within "#list-rail" do
      find(".dm-conversation", text: "Jason").click
    end

    assert_selector ".navbar-title", text: "Jason"
    assert_selector "#list-rail .dm-conversation", minimum: 2
  end

  test "narrow widths keep the conversation full-width without the rail" do
    visit room_url(rooms(:david_and_kevin))
    page.current_window.resize_to(700, 900)

    assert_no_selector "#list-rail .dm-conversation"
    assert_selector "#composer"
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
