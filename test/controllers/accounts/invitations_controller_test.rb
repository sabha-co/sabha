require "test_helper"

class Accounts::InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the join link and the mint-your-own toggle inside the settings shell" do
    get account_invitations_url

    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Invitations"
    assert_select "input#invite_url[value=?]", join_url(accounts(:signal).join_code.code)
    assert_select "form[action=?]", account_join_code_path
    assert_select "input[type=hidden][name=?]", "account[settings][allow_users_to_create_invite_links]"
  end

  test "non-admins cannot access invitations" do
    sign_in :kevin

    get account_invitations_url
    assert_redirected_to root_path
  end
end
