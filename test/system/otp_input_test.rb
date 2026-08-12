require "application_system_test_case"

# The six-cell one-time-code field (otp-input controller) behaves as a single
# input: it normalizes like the server's OtpCode, advances across cells as you
# type, spreads a paste/autofill, and mirrors the whole value into the hidden
# `code` param the form actually submits.
class OtpInputTest < ApplicationSystemTestCase
  test "the client normalizer matches the server's OtpCode.sanitize" do
    visit new_session_path

    result = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("models/otp_code").then(({ sanitize }) => {
        done([
          sanitize("aob"),         // uppercase, O->0
          sanitize("aib"),         // I->1
          sanitize("alb"),         // L->1
          sanitize("ABC 123"),     // strip spaces
          sanitize("A-B-C-1-2-3"), // strip dashes
          sanitize(null)           // nil-safe
        ])
      })
    JS

    assert_equal [ "A0B", "A1B", "A1B", "ABC123", "ABC123", "" ], result
  end

  test "cells normalize on input, advance focus, spread a paste, and mirror the hidden code" do
    with_otp_auth do
      visit new_session_path
      find("input[name='email_address']").set("david@37signals.com")
      click_on "Sign in with email"

      cells = all(".otp__cell")
      assert_equal 6, cells.size

      # Normalization happens on the way in: "o" is stored as "0".
      cells.first.send_keys("o")
      assert_equal "0", cells.first.value

      # Focus advanced to the second cell.
      assert_equal "Character 2 of 6", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

      # A multi-character input (paste or OS autofill landing in one cell)
      # spreads across the cells and mirrors into the hidden `code` field.
      page.execute_script(<<~JS, cells.first.native)
        const cell = arguments[0]
        cell.value = "abcd12"
        cell.dispatchEvent(new Event("input", { bubbles: true }))
      JS

      assert_equal %w[A B C D 1 2], all(".otp__cell").map(&:value)
      assert_equal "ABCD12", find("input[name='code']", visible: false).value
    end
  end

  private
    def with_otp_auth
      original = ENV["AUTH_METHOD"]
      ENV["AUTH_METHOD"] = "otp"
      yield
    ensure
      original.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original
    end
end
