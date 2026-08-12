require "application_system_test_case"

class MessageRetryTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
  end

  test "a failed send keeps the draft on screen and retry delivers it" do
    make_next_fetch_fail

    send_message "Hello from a dead zone"

    assert_selector ".message--failed"
    assert_selector ".message__failed-notice", text: /Couldn’t send. Your message is still here./

    click_on "Retry"

    assert_no_selector ".message--failed"
    assert_no_selector ".message__failed-notice"
    assert_message_text "Hello from a dead zone"
    assert_includes rooms(:designers).messages.last.plain_text_body, "Hello from a dead zone"
  end

  test "a failed send leaves nothing behind on the server until retried" do
    count_before = rooms(:designers).messages.count

    make_next_fetch_fail
    send_message "Lost in transit"

    assert_selector ".message--failed"
    assert_equal count_before, rooms(:designers).messages.count
  end

  private
    # Simulates a network blip: the next fetch (the Turbo form submission)
    # rejects, then the original fetch is restored so a retry can succeed.
    def make_next_fetch_fail
      execute_script <<~JS
        const original = window.fetch
        window.fetch = (...args) => {
          window.fetch = original
          return Promise.reject(new TypeError("Network request failed"))
        }
      JS
    end
end
