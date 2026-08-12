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

  test "the options menu opens as a dialog and closes when an item is chosen" do
    within_message messages(:third) do
      reveal_message_actions
    end

    assert_selector "dialog[aria-label='Message options'][open]"

    within "dialog[aria-label='Message options'][open]" do
      click_on "Copy link"
    end

    assert_no_selector "dialog[aria-label='Message options'][open]"
  end

  test "a quick reaction from the action bar boosts the message" do
    within_message messages(:third) do
      find(".message__body-content").hover
      find(".message__quick-reaction button[title='Thumbs up']").click

      # Your own chip carries the accent tint (stamped client-side)
      assert_selector ".boost.boost--mine", text: "👍"
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
