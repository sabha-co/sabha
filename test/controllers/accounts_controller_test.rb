require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "edit" do
    get edit_account_url
    assert_response :ok
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

  test "non-admins can access edit as read-only about page" do
    sign_in :kevin
    assert users(:kevin).member?

    get edit_account_url
    assert_response :success
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
