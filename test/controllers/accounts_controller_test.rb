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

  test "non-admins cannot access edit" do
    sign_in :kevin
    assert users(:kevin).member?

    get edit_account_url
    assert_redirected_to root_path
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

  test "edit page shows administrators before members with divider" do
    get edit_account_url
    assert_response :ok

    # Check that divider exists when there are both admins and members
    assert_select "hr.separator.full-width"

    # Verify the response body has admin before the divider and member after
    body = response.body
    divider_pos = body.index("separator full-width")
    admin_pos = body.index(users(:david).name)
    member_pos = body.index(users(:kevin).name)

    assert admin_pos < divider_pos, "Administrator should appear before the divider"
    assert divider_pos < member_pos, "Member should appear after the divider"
  end
end
