require "application_system_test_case"

# Regression wall for the settings/members surfaces the v2 reskin restyles, and
# for the permission boundary the redesign must preserve: the members directory
# is open to everyone, but only administrators get the account-configuration
# affordance. Asserts through email/name text and the edit link, so it survives
# the reskin (and stays true when the 403 gate becomes a styled page).
class SettingsAndMembershipTest < ApplicationSystemTestCase
  test "a member can open their own profile settings" do
    sign_in "kevin@37signals.com"
    visit user_profile_path

    assert_selector "input[value='kevin@37signals.com']"
  end

  test "the members directory is open to every member" do
    sign_in "kevin@37signals.com"   # a non-administrator
    visit account_users_path

    assert_text "David"
    assert_text "Jason"
  end

  test "administrators get the account-configuration link" do
    sign_in "david@37signals.com"   # administrator
    visit account_path

    assert_selector "a[href='#{edit_account_path}']"
  end

  test "members do not get the account-configuration link" do
    sign_in "kevin@37signals.com"   # a non-administrator
    visit account_path

    assert_no_selector "a[href='#{edit_account_path}']"
  end

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
