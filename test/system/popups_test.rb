require "application_system_test_case"

# Characterization coverage for the two popup controllers (popup, mention-popup)
# before they are refactored onto a shared base. The open path is exercised
# elsewhere (reveal_message_actions across the messaging tests; composer_test for
# the mention popup); these pin the close lifecycle — closeOnClickOutside → close
# → the animationend #finishClose — which no test touched before, and which is the
# code moving to the base class.
class PopupsTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
  end

  test "the message-actions popup opens and closes on an outside click" do
    within_message messages(:third) do
      reveal_message_actions
      assert_selector ".message__boost-btn", visible: true
    end

    # A click that lands outside the open <details> runs closeOnClickOutside.
    find("#composer").click

    within_message messages(:third) do
      assert_no_selector ".message__boost-btn", visible: true
      assert_no_selector "details[open]"
    end
  end

  test "the mention profile popup opens and closes on an outside click" do
    type_in_composer "Morning @Jas"
    pick_mention "Jason"
    click_on "send"

    within last_message_selector(".mention") do
      find(".mention__summary").click
      assert_selector ".mention__summary[aria-expanded='true']"
    end
    assert_selector "#{last_message_selector(".mention")}[data-open]"

    find("#composer").click

    assert_no_selector "#{last_message_selector(".mention")}[data-open]"
    within last_message_selector(".mention") do
      assert_selector ".mention__summary[aria-expanded='false']"
    end
  end

  private
    def last_message_selector(inner)
      ".message:last-of-type .message__body #{inner}"
    end
end
