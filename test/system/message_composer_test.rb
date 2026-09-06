require "application_system_test_case"

# Single-session regression wall for the composer → message-row path the v2
# reskin restyles (Step 3: square avatars, floating action bar, relocated typing
# indicator). Deliberately single-session and navigated by sidebar click — it
# does not depend on the cross-client real-time delivery the (flaky) multi-session
# `sending_messages_test` exercises, so it stays a reliable signal.
class MessageComposerTest < ApplicationSystemTestCase
  setup { sign_in "kevin@37signals.com" }

  # A couple of tests below resize to a phone; reset so the width can't leak
  # into the tests that follow in the same browser session.
  teardown { page.current_window.resize_to(1400, 1400) }

  test "the typing indicator floats above the composer and reserves no space" do
    click_on "Designers"
    dismiss_pwa_install_prompt

    row = find(".composer .typing-indicator", visible: :all)
    # Out-of-flow overlay: it never contributes height, so the composer can't
    # shift when someone starts or stops typing.
    assert_equal "absolute", row.evaluate_script("getComputedStyle(this).position")
    assert_equal 22, row.evaluate_script("Math.round(this.getBoundingClientRect().height)")

    # It floats above the composer card rather than pushing it down.
    card_top = find(".composer .composer__row").evaluate_script("Math.round(this.getBoundingClientRect().top)")
    row_bottom = row.evaluate_script("Math.round(this.getBoundingClientRect().bottom)")
    assert_operator row_bottom, :<=, card_top + 1
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

  test "on a phone the composer keeps 44px tap targets and reveals the format bar on focus" do
    page.current_window.resize_to(390, 800)

    find("#sidebar-toggle").click
    click_on "Designers"
    dismiss_pwa_install_prompt

    # The tools row meets the 44px minimum tap target.
    %w[.composer__send-btn .composer__emoji-btn .composer__attachment-btn].each do |selector|
      height = find(selector).evaluate_script("Math.round(this.getBoundingClientRect().height)")
      assert_operator height, :>=, 44, "#{selector} is #{height}px tall, below the 44px minimum"
    end

    # The format bar reveals only while the field has focus. The composer
    # auto-focuses on load, so blur it first to observe the resting (hidden) state.
    page.execute_script("document.activeElement?.blur()")
    assert_no_selector "#composer lexxy-toolbar", visible: true
    composer_editor.click
    assert_selector "#composer lexxy-toolbar", visible: true
  end

  test "on a phone Jump to newest floats over the transcript above the composer" do
    room = rooms(:designers)
    18.times do |i|
      room.messages.create!(
        creator: [ users(:jason), users(:david), users(:jz) ][i % 3],
        body: "Older message #{i}",
        client_message_id: "phone_jump_#{i}",
        created_at: (20 - i).minutes.ago
      )
    end

    page.current_window.resize_to(390, 800)
    find("#sidebar-toggle").click
    click_on "Designers"
    dismiss_pwa_install_prompt

    messages = find(".messages")
    page.execute_script("arguments[0].scrollTo(0, 0)", messages)
    assert_selector ".message-area__return-to-latest", visible: true

    [ "", "<p>Draft line</p>" * 12 ].each do |draft|
      fill_in_rich_text_area "message_body", with: draft
      assert_composer_text "Draft line" unless draft.empty?

      geometry = page.evaluate_script(<<~JS)
        (() => {
          const messages = document.querySelector(".messages").getBoundingClientRect()
          const button = document.querySelector(".message-area__return-to-latest").getBoundingClientRect()
          const composer = document.querySelector("#composer").getBoundingClientRect()
          return { messagesBottom: messages.bottom, buttonTop: button.top, buttonBottom: button.bottom, composerTop: composer.top }
        })()
      JS

      assert_operator geometry["messagesBottom"], :>=, geometry["buttonBottom"],
                      "expected messages to continue behind Jump to newest without a separate blank row"
      assert_operator geometry["buttonBottom"], :<=, geometry["composerTop"],
                      "expected Jump to newest to clear the composer"
    end

    click_on "Jump to newest"
    assert_no_selector ".message-area__return-to-latest", visible: true
    assert_composer_text "Draft line"
  end
end
