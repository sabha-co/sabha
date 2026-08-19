require "application_system_test_case"

# Pins the message-row contracts the v2 reskin restyles: client-side grouping
# of consecutive same-author messages, and the reveal of the row's actions.
# Single-session on purpose — no cross-client delivery, so it stays reliable.
class MessageRowTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    # Navigate by sidebar click rather than join_room's visit — same reasoning
    # as message_composer_test, it avoids the post-visit stream-source race.
    click_on "Designers"
    dismiss_pwa_install_prompt
  end

  test "consecutive messages from the same author group as a follow-on" do
    send_message "First of a pair"
    send_message "Second of a pair"

    assert_selector ".message.message--threaded", text: "Second of a pair"
  end

  test "hovering a message reveals its actions" do
    message = find(".message", text: "Third time's a charm.")
    assert_message_actions_hidden message

    message.hover
    assert_message_actions_revealed message
  end

  test "keyboard focus inside a message reveals its actions" do
    message = find(".message", text: "Third time's a charm.")
    assert_message_actions_hidden message

    message.find(".message__author").evaluate_script("this.focus()")
    assert_message_actions_revealed message
  end

  test "the options menu opens as an anchored popover and closes when an item is chosen" do
    within_message messages(:third) do
      reveal_message_actions
    end

    assert_selector ".message-menu", visible: :visible
    assert_no_selector "dialog[aria-label='Message options'][open]"
    assert_selector ".options-btn[aria-expanded='true']"

    within ".message-menu" do
      click_on "Copy link"
    end

    assert_no_selector ".message-menu", visible: :visible
    assert_no_selector ".options-btn[aria-expanded='true']"
  end

  test "the options menu anchors to its trigger inside the viewport" do
    within_message messages(:third) do
      reveal_message_actions
    end
    assert_selector ".message-menu", visible: :visible

    anchored = page.evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector(".options-btn[aria-expanded='true']")
        const menu = trigger.closest("[data-controller~='popover']").querySelector(".message-menu")
        const t = trigger.getBoundingClientRect(), m = menu.getBoundingClientRect()
        const rightAligned = Math.abs(t.right - m.right) < 2
        const inViewport = m.left >= 10 && m.top >= 10 &&
          m.right <= window.innerWidth - 10 && m.bottom <= window.innerHeight - 10
        return rightAligned && inViewport
      })()
    JS
    assert anchored, "expected the menu right-aligned to its trigger and clamped inside the viewport"
  end

  test "right-clicking a message opens its options menu" do
    find(".message", text: "Third time's a charm.").right_click

    assert_selector ".message-menu", visible: :visible
  end

  test "the options menu closes on outside click and on Escape" do
    within_message messages(:third) do
      reveal_message_actions
    end
    assert_selector ".message-menu", visible: :visible

    find("#nav").click
    assert_no_selector ".message-menu", visible: :visible

    within_message messages(:third) do
      reveal_message_actions
    end
    assert_selector ".message-menu", visible: :visible

    find("body").send_keys :escape
    assert_no_selector ".message-menu", visible: :visible
  end

  test "clicking a message avatar opens the quick profile as an anchored popover" do
    within_message messages(:third) do
      find(".message__avatar button.avatar").click
    end

    assert_selector ".message__avatar-menu .quick-profile", visible: :visible

    find("#nav").click
    assert_no_selector ".message__avatar-menu .quick-profile", visible: :visible
  end

  test "the action bar reflects a reaction the user has made and toggles it off" do
    within_message messages(:third) do
      find(".message__body-content").hover
      find(".message__quick-reaction button[title='Thumbs up']").click

      # The reaction lands and its quick-reaction now reads as active.
      assert_selector ".boost.boost--mine", text: "👍"
      assert_selector ".message__quick-reaction--active button[title='Thumbs up']"

      # Clicking the active quick-reaction removes the reaction again.
      find(".message__body-content").hover
      find(".message__quick-reaction--active button[title='Thumbs up']").click

      assert_no_selector ".boost", text: "👍"
      assert_no_selector ".message__quick-reaction--active"
    end
  end

  private
    # The reveal is opacity/visibility-based, which Capybara's :visible filter
    # ignores, so assert on computed style.
    def assert_message_actions_revealed(message)
      button = message.find(".message__options-btn", match: :first, visible: :all)
      assert_equal "visible", button.evaluate_script("getComputedStyle(this).visibility")
      assert_equal "1", button.evaluate_script("getComputedStyle(this).opacity")
    end

    def assert_message_actions_hidden(message)
      button = message.find(".message__options-btn", match: :first, visible: :all)
      hidden = button.evaluate_script(
        "getComputedStyle(this).opacity === '0' || getComputedStyle(this).visibility === 'hidden'"
      )
      assert hidden, "expected the message actions to be hidden before hover"
    end
end
