require "test_helper"

class Accounts::PermissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the restriction toggles inside the settings shell" do
    get account_permissions_url

    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Permissions"
    assert_select "input[type=hidden][name=?]", "account[settings][restrict_room_creation_to_administrators]"
    assert_select "input[type=hidden][name=?]", "account[settings][restrict_direct_messages_to_administrators]"
    assert_visible_toggle "Must be admin to create new rooms"
    assert_visible_toggle "Must be admin to start DMs"
  end

  test "show carries the community email toggles" do
    get account_permissions_url

    assert_select "input[type=hidden][name=?]", "account[email_notifications_enabled]"
    assert_select "input[type=hidden][name=?]", "account[weekly_digest_enabled]"
    assert_visible_toggle "Send missed-notification emails"
    assert_visible_toggle "Send the weekly community digest"
  end

  test "the invite-links toggle lives on invitations, not permissions" do
    get account_permissions_url

    assert_select "input[type=hidden][name=?]", "account[settings][allow_users_to_create_invite_links]", count: 0
  end

  test "non-admins cannot access permissions" do
    sign_in :kevin

    get account_permissions_url
    assert_redirected_to root_path
  end

  private
    def assert_visible_toggle(title)
      row = css_select("label.setting-row").find { |element| element.text.include?(title) }

      assert row, "expected a visible setting row for #{title.inspect}"
      assert_select row, "input.switch__input[type=checkbox]", count: 1
    end
end
