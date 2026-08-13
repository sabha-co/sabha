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

  test "starting a conversation from the rail compose bar" do
    visit inbox_direct_messages_url

    fill_in "user_ids_input", with: "Jason"
    find("suggestion-option", text: "Jason").click

    # The picked pill must not push the submit arrow past the rail's clipped
    # edge — the regression that made the compose flow dead-end
    assert_predicate self, :submit_button_inside_rail?

    find(".dm-compose__submit").click

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

  private
    def submit_button_inside_rail?
      page.evaluate_script(<<~JS)
        (() => {
          const rail = document.querySelector("#list-rail").getBoundingClientRect()
          const btn = document.querySelector(".dm-compose__submit").getBoundingClientRect()
          return btn.width > 0 && btn.right <= rail.right + 1 && btn.left >= rail.left - 1
        })()
      JS
    end
end
