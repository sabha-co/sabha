require "test_helper"

class Users::InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "members can view their invitation page when personal invites are enabled" do
    get user_invitations_url

    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Invitations"
    assert_select "form[action=?]", user_invite_link_path
  end

  test "members cannot view their invitation page when personal invites are disabled" do
    Account.sole.tap do |account|
      account.settings.allow_users_to_create_invite_links = false
      account.save!
    end

    get user_invitations_url

    assert_redirected_to user_profile_path
  end

  test "administrators see their personal invitation page in the personal settings rail" do
    sign_in :david

    get user_invitations_url

    assert_select ".settings-nav__title", text: "Your settings"
    assert_select ".settings-nav__item[aria-current=page]", text: "Invitations"
    assert_select ".settings-nav__item", text: "Members", count: 0
  end
end
