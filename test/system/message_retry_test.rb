require "application_system_test_case"

class MessageRetryTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
  end

  test "a failed send keeps the draft on screen and retry delivers it" do
    count_before = rooms(:designers).messages.count
    make_next_fetch_lose_response

    send_message "Hello from a dead zone"

    assert_selector ".message--failed"
    assert_selector ".message__failed-notice", text: /Not sent/
    assert_equal count_before + 1, rooms(:designers).messages.count,
      "the server persisted the send before its response was lost"

    click_on "Try again"

    assert_no_selector ".message--failed"
    assert_no_selector ".message__failed-notice"
    assert_message_text "Hello from a dead zone"
    assert_equal count_before + 1, rooms(:designers).messages.count,
      "retry should replay the persisted message instead of duplicating it"
    assert_includes rooms(:designers).messages.last.plain_text_body, "Hello from a dead zone"
  end

  test "a failed send leaves nothing behind on the server until retried" do
    count_before = rooms(:designers).messages.count

    make_next_fetch_fail_before_request
    send_message "Lost in transit"

    assert_selector ".message--failed"
    assert_equal count_before, rooms(:designers).messages.count
  end

  private
    # Simulates losing the response after Rails has persisted the send. Retrying
    # must reuse the client message ID and render the already-created message.
    # Drop the live stream too, matching the same dead connection; otherwise its
    # broadcast would deliver the message even though the POST response vanished.
    def make_next_fetch_lose_response
      execute_script <<~JS
        document.querySelectorAll("turbo-cable-stream-source").forEach((source) => source.remove())

        const original = window.fetch
        window.fetch = (...args) => {
          window.fetch = original
          return original(...args).then(() => {
            throw new TypeError("Network response was lost")
          })
        }
      JS
    end

    # Simulates an offline request that never reaches Rails.
    def make_next_fetch_fail_before_request
      execute_script <<~JS
        const original = window.fetch
        window.fetch = (...args) => {
          window.fetch = original
          return Promise.reject(new TypeError("Network request failed"))
        }
      JS
    end
end
