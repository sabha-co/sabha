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
  end

  test "show carries the community email toggles" do
    get account_permissions_url

    assert_select "input[type=hidden][name=?]", "account[email_notifications_enabled]"
    assert_select "input[type=hidden][name=?]", "account[weekly_digest_enabled]"
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
end
