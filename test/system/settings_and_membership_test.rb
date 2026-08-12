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
end
