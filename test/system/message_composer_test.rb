require "application_system_test_case"

# Single-session regression wall for the composer → message-row path the v2
# reskin restyles (Step 3: square avatars, floating action bar, relocated typing
# indicator). Deliberately single-session and navigated by sidebar click — it
# does not depend on the cross-client real-time delivery the (flaky) multi-session
# `sending_messages_test` exercises, so it stays a reliable signal.
class MessageComposerTest < ApplicationSystemTestCase
  setup { sign_in "kevin@37signals.com" }

  test "a sent message appears in the conversation" do
    click_on "Designers"
    dismiss_pwa_install_prompt

    send_message "Regression wall says hi"
    assert_message_text "Regression wall says hi"
  end

  test "the typing indicator is a reserved static row so the composer never shifts" do
    click_on "Designers"
    dismiss_pwa_install_prompt

    row = find(".composer .typing-indicator", visible: :all)
    assert_equal "static", row.evaluate_script("getComputedStyle(this).position")
    assert_equal 22, row.evaluate_script("Math.round(this.getBoundingClientRect().height)")
  end

  test "send carries the accent state only while the draft is non-empty" do
    click_on "Designers"
    dismiss_pwa_install_prompt

    assert_no_selector "#composer.composer--drafting"

    fill_in_rich_text_area "message_body", with: "Drafting now"
    assert_selector "#composer.composer--drafting"

    click_on "send"
    assert_message_text "Drafting now"
    assert_no_selector "#composer.composer--drafting"
  end

  test "typing labels read naturally at every crowd size" do
    click_on "Designers"
    dismiss_pwa_install_prompt

    labels = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("models/typing_tracker").then(({ default: TypingTracker }) => {
        done([
          TypingTracker.label([]) ?? "EMPTY", // Cuprite drops null array entries
          TypingTracker.label(["Naima Okafor"]),
          TypingTracker.label(["Naima Okafor", "Theo Marchetti"]),
          TypingTracker.label(["Naima Okafor", "Theo Marchetti", "Iris Holm"]),
          TypingTracker.label(["Naima Okafor", "Theo Marchetti", "Iris Holm", "Sarah Whitfield"])
        ])
      })
    JS

    assert_equal [
      "EMPTY",
      "Naima Okafor is typing",
      "Naima and Theo are typing",
      "Naima, Theo and 1 other are typing",
      "Naima, Theo and 2 others are typing"
    ], labels
  end
end
