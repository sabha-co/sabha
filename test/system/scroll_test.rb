require "application_system_test_case"

# End-to-end smoke coverage for the ScrollManager → ScrollGeometry wiring after
# the extraction. This exercises the *force* autoscroll path only (the composer's
# optimistic insert and the connect-time scroll both call autoscroll(true)), so it
# proves the refactored ScrollManager constructs its ScrollGeometry, keeps the
# view pinned to the newest message, and throws nowhere.
#
# It deliberately does NOT characterize the cached near-end decision
# (#scrolledNearEnd → ScrollGeometry#distanceScrolledFromEnd): that reads the RAF
# cache and is only reached from autoscroll(false) in the incoming-stream handler,
# which needs live cable delivery this harness doesn't provide. That path is
# tracked separately (see the review note) — it wants a JS-level unit test or a
# synthetic turbo-stream injection over a scrollable message set.
class ScrollTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
  end

  test "sending a message keeps the container pinned to the newest message" do
    send_message "Bottom of the thread"
    assert_message_text "Bottom of the thread"

    assert_scrolled_to_bottom rooms(:designers)
  end

  private
    # The messages container (ScrollManager's element) is pinned to the bottom when
    # scrollHeight - scrollTop - clientHeight is within a small slack. A couple of
    # pixels of rounding is expected; anything larger means autoscroll didn't fire.
    def assert_scrolled_to_bottom(room, slack: 4)
      selector = "##{dom_id(room, :messages)}"
      distance = page.evaluate_script(<<~JS)
        (() => { const el = document.querySelector("#{selector}");
                 return el ? el.scrollHeight - el.scrollTop - el.clientHeight : null })()
      JS
      assert_not_nil distance, "expected to find the messages container #{selector}"
      assert_operator distance, :<=, slack, "expected container pinned to bottom, was #{distance}px away"
    end
end
