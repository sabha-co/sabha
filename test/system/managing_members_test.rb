require "application_system_test_case"

class ManagingMembersTest < ApplicationSystemTestCase
  setup do
    sign_in "david@37signals.com"
    visit account_users_url
  end

  test "changing a member's role from the manage dialog" do
    open_manage_dialog users(:kevin)

    within_manage_dialog do
      click_on "Moderator"
    end

    assert_manage_dialog_closed
    assert_selector "#moderators_section turbo-frame#" + dom_id(users(:kevin))
    assert users(:kevin).reload.moderator?
  end

  test "assigning a badge from the manage dialog" do
    open_manage_dialog users(:kevin)

    within_manage_dialog do
      click_on "VIP"
    end

    assert_manage_dialog_closed
    assert_equal badges(:vip), users(:kevin).reload.badge
  end

  test "deactivating a member from the manage dialog" do
    open_manage_dialog users(:kevin)

    accept_confirm do
      within_manage_dialog do
        click_on "Deactivate"
      end
    end

    assert_no_selector "turbo-frame#" + dom_id(users(:kevin))
    assert_not users(:kevin).reload.active?
  end

  test "the manage dialog closes on escape without changes" do
    role_before = users(:kevin).reload.role

    open_manage_dialog users(:kevin)

    # A bare keyboard escape — element-targeted send_keys clicks the card to
    # focus it, which would land on a role row.
    page.driver.browser.keyboard.type(:Escape)

    assert_manage_dialog_closed
    assert_equal role_before, users(:kevin).reload.role
  end

  private
    def open_manage_dialog(user)
      within "turbo-frame#" + dom_id(user) do
        click_on "Manage"
      end

      assert_selector "#manage_member_dialog[open]"
    end

    def within_manage_dialog(&block)
      within "#manage_member_dialog", &block
    end

    def assert_manage_dialog_closed
      assert_no_selector "#manage_member_dialog[open]"
    end
end
