require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show is accessible to admins" do
    get account_url
    assert_response :ok
  end

  test "show is accessible to non-admins as the about page" do
    sign_in :kevin
    assert users(:kevin).member?

    get account_url
    assert_response :success
  end

  test "edit" do
    get edit_account_url
    assert_response :ok
  end

  test "edit renders inside the settings shell with Identity current" do
    get edit_account_url

    assert_select ".settings-nav__item", count: 5
    assert_select ".settings-nav__item[aria-current=page]", text: "Identity"
    assert_select "a.settings-nav__switch[href=?]", user_profile_path, text: /Your settings/
    assert_select "input[name=?]", "account[settings][accent]"
  end

  test "the restriction toggles moved off the identity page" do
    get edit_account_url

    assert_select "input[type=hidden][name=?]", "account[settings][restrict_room_creation_to_administrators]", count: 0
    assert_select "input[type=hidden][name=?]", "account[email_notifications_enabled]", count: 0
  end

  test "update returns to the settings page it came from" do
    put account_url,
        params: { account: { settings: { restrict_direct_messages_to_administrators: true } } },
        headers: { "HTTP_REFERER" => account_permissions_url }

    assert_redirected_to account_permissions_url
    assert accounts(:signal).reload.settings.restrict_direct_messages_to_administrators?
  end

  test "non-admins cannot access edit" do
    sign_in :kevin
    assert users(:kevin).member?

    get edit_account_url
    assert_redirected_to root_path
  end

  test "update" do
    assert users(:david).administrator?

    put account_url, params: { account: { name: "Different" } }

    assert_redirected_to edit_account_url
    assert_equal accounts(:signal).name, "Different"
  end

  test "non-admins cannot update" do
    sign_in :kevin
    assert users(:kevin).member?

    put account_url, params: { account: { name: "Different" } }
    assert_redirected_to root_path
  end

  test "admin can pick a workspace accent" do
    put account_url, params: { account: { settings: { accent: "forest" } } }

    assert_redirected_to edit_account_url
    assert_equal "forest", accounts(:signal).reload.settings.accent
  end

  test "the layout stamps the workspace accent on the html element" do
    accounts(:signal).update!(settings: { "accent" => "plum" })

    get user_profile_url

    assert_select "html[data-accent=?]", "plum"
  end

  test "the layout falls back to indigo when no accent is stored" do
    get user_profile_url

    assert_select "html[data-accent=?]", "indigo"
  end

  test "admin can flip email_notifications_enabled" do
    assert_not accounts(:signal).email_notifications_enabled?

    put account_url, params: { account: { email_notifications_enabled: true } }

    assert_redirected_to edit_account_url
    assert accounts(:signal).reload.email_notifications_enabled?
  end

  test "admin can flip weekly_digest_enabled" do
    assert_not accounts(:signal).weekly_digest_enabled?

    put account_url, params: { account: { weekly_digest_enabled: true } }

    assert_redirected_to edit_account_url
    assert accounts(:signal).reload.weekly_digest_enabled?
  end

  test "non-admin cannot flip email_notifications_enabled" do
    sign_in :kevin
    assert users(:kevin).member?

    put account_url, params: { account: { email_notifications_enabled: true } }

    assert_redirected_to root_path
    assert_not accounts(:signal).reload.email_notifications_enabled?
  end

  test "updating one setting does not overwrite other settings" do
    # First, enable room creation restriction
    accounts(:signal).settings.restrict_room_creation_to_administrators = true
    accounts(:signal).save!

    assert accounts(:signal).reload.settings.restrict_room_creation_to_administrators?
    assert_not accounts(:signal).settings.restrict_direct_messages_to_administrators?

    # Now enable DM restriction - this should NOT reset room creation restriction
    put account_url, params: { account: { settings: { restrict_direct_messages_to_administrators: true } } }

    assert_redirected_to edit_account_url
    accounts(:signal).reload

    # Both settings should be enabled
    assert accounts(:signal).settings.restrict_room_creation_to_administrators?, "Room creation restriction was overwritten"
    assert accounts(:signal).settings.restrict_direct_messages_to_administrators?, "DM restriction was not saved"
  end
end
