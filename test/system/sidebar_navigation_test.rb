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

  test "the footer profile row opens its anchored flyout" do
    trigger = find(".sidebar__me")

    trigger.click

    assert_selector ".sidebar__me[aria-expanded='true']"
    within ".sidebar__profile-popover" do
      assert_link "View profile"
      assert_link "Your settings"
      assert_link "Appearance"
      assert_link "Invitations"
      assert_no_link "Community settings"
      assert_button "Log out"
    end
    assert_selector ".sidebar__footer > .sidebar__profile", count: 1
    assert_selector ".sidebar__footer > *", count: 1

    trigger.send_keys :tab
    assert page.evaluate_script("document.activeElement.matches('.sidebar__profile-summary')")
    assert_equal "solid", page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle")
  end

  test "the profile flyout flips upward and stays inside desktop, rail, and drawer viewports" do
    [ [ 1400, 1400, false ], [ 1024, 768, false ], [ 390, 844, true ] ].each do |width, height, drawer|
      page.current_window.resize_to(width, height)
      find("#sidebar-toggle").click if drawer && page.has_no_css?("#sidebar.open")
      assert_no_selector ".sidebar__me-caret", visible: true if width == 1024

      trigger = find(".sidebar__me", visible: true)
      trigger.click
      assert_selector ".sidebar__profile-popover", visible: true

      geometry = page.evaluate_script(<<~JS)
        (() => {
          const trigger = document.querySelector(".sidebar__me").getBoundingClientRect()
          const menu = document.querySelector(".sidebar__profile-popover").getBoundingClientRect()
          return { top: menu.top, right: menu.right, bottom: menu.bottom, left: menu.left,
                   triggerTop: trigger.top, width: window.innerWidth, height: window.innerHeight }
        })()
      JS

      assert_operator geometry["top"], :>=, 12
      assert_operator geometry["left"], :>=, 12
      assert_operator geometry["right"], :<=, geometry["width"] - 12
      assert_operator geometry["bottom"], :<=, geometry["height"] - 12
      assert_operator geometry["bottom"], :<, geometry["triggerTop"]

      find("body").send_keys :escape
      assert_selector ".sidebar__me[aria-expanded='false']"
    end
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "the open profile flyout follows its trigger after a viewport resize" do
    page.current_window.resize_to(1400, 900)
    find(".sidebar__me").click
    menu = find(".sidebar__profile-popover", visible: true)
    initial_block_start = menu.evaluate_script("this.style.insetBlockStart")

    page.current_window.resize_to(1024, 700)

    assert_no_selector ".sidebar__profile-popover[style*='inset-block-start: #{initial_block_start}']"
    geometry = menu.evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector(".sidebar__me").getBoundingClientRect()
        const menu = this.getBoundingClientRect()
        return { top: menu.top, bottom: menu.bottom, triggerTop: trigger.top, height: window.innerHeight }
      })()
    JS
    assert_operator geometry["top"], :>=, 12
    assert_operator geometry["bottom"], :<=, geometry["height"] - 12
    assert_operator geometry["bottom"], :<, geometry["triggerTop"]
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "the profile flyout scrolls within a short viewport" do
    page.current_window.resize_to(390, 220)
    find("#sidebar-toggle").click if page.has_no_css?("#sidebar.open")
    find(".sidebar__me", visible: true).click
    menu = find(".sidebar__profile-popover", visible: true)

    geometry = menu.evaluate_script(<<~JS)
      (() => {
        const menu = this.getBoundingClientRect()
        const styles = getComputedStyle(this)
        return { top: menu.top, bottom: menu.bottom, height: window.innerHeight,
                 overflowY: styles.overflowY, clientHeight: this.clientHeight, scrollHeight: this.scrollHeight }
      })()
    JS
    assert_operator geometry["top"], :>=, 12
    assert_operator geometry["bottom"], :<=, geometry["height"] - 12
    assert_equal "auto", geometry["overflowY"]
    assert_operator geometry["scrollHeight"], :>, geometry["clientHeight"]

    menu.evaluate_script("this.scrollTop = this.scrollHeight")
    within menu do
      assert_button "Log out", visible: true
    end
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "logging out from the profile flyout ends the session" do
    find(".sidebar__me").click
    within ".sidebar__profile-popover" do
      click_on "Log out"
    end

    assert_current_path new_session_path
    assert_button "Sign in"
  end
end
