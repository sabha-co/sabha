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
end
