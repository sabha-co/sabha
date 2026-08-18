require "application_system_test_case"

# Regression wall for applying a workspace accent through the browser and
# repainting the app with the selected value.
class SettingsAndMembershipTest < ApplicationSystemTestCase
  test "an administrator picks a workspace accent and the app repaints with it" do
    sign_in "david@37signals.com"
    visit edit_account_path

    assert_selector "html[data-accent='indigo']"
    find(".accent-swatch", text: "Forest").click

    # The picker form opts out of Turbo, so the save round-trips a full page
    # load and the html element carries the new accent.
    assert_selector "html[data-accent='forest']"
    accent = page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('--lch-accent')")
    assert_includes accent, "165", "expected the forest hue to be live, got #{accent.inspect}"
  end
end
