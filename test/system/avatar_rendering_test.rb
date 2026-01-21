require "application_system_test_case"

class AvatarRenderingTest < ApplicationSystemTestCase
  # System test for avatar rendering in the browser.
  # Detailed caching behavior is tested in unit tests.

  test "avatars render in room messages" do
    sign_in "kevin@37signals.com"

    # Click the room link from the sidebar to avoid Turbo stale element issues
    click_on "Designers"
    dismiss_pwa_install_prompt

    assert_selector ".message", minimum: 1

    # Avatars should be present as images (served via controller)
    assert_selector ".avatar img", minimum: 1
  end
end
