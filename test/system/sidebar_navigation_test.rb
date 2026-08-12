require "application_system_test_case"

# Regression wall for the sidebar → room navigation the v2 shell rework touches
# (sidebar moves right→left, gains a rail/drawer state machine). Asserts the
# behaviour — the sidebar lists joined rooms and clicking one opens its
# conversation — through room-name text and the stable `.rooms`/`.message`/
# `.composer` contracts, not the current layout, so it survives the reskin.
class SidebarNavigationTest < ApplicationSystemTestCase
  setup { sign_in "kevin@37signals.com" }

  test "the sidebar lists a joined room and opening it loads the conversation" do
    within ".rooms" do
      assert_link "Designers"
    end

    click_on "Designers"
    dismiss_pwa_install_prompt

    assert_selector ".message", minimum: 1   # the room's message stream rendered
    assert_selector ".composer"              # and its composer is present
  end
end
