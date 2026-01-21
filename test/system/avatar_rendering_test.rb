require "application_system_test_case"

class AvatarRenderingTest < ApplicationSystemTestCase
  # System test for avatar rendering in the browser.
  # Detailed caching behavior is tested in unit tests.

  setup do
    # Ensure WebMock is disabled for system tests (unit tests may re-enable it)
    WebMock.disable!
  end

  test "avatars render in room messages" do
    sign_in_via_marketing "kevin@37signals.com"

    # Click the room link from the sidebar to avoid Turbo stale element issues
    click_on "Designers"
    dismiss_pwa_install_prompt

    assert_selector ".message", minimum: 1

    # Avatars should be present as images (served via controller)
    assert_selector ".avatar img", minimum: 1
  end

  private

  def sign_in_via_marketing(email_address, password = "secret123456")
    visit root_url
    click_on "Sign In"

    fill_in "email_address", with: email_address
    fill_in "password", with: password

    click_on "log_in"
    assert_selector "a.btn", text: "Designers"
  end
end
