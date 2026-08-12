require "application_system_test_case"

# Pins the message-row contracts the v2 reskin restyles: client-side grouping
# of consecutive same-author messages, and the reveal of the row's actions.
# Single-session on purpose — no cross-client delivery, so it stays reliable.
class MessageRowTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
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
