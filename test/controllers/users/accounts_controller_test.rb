require "test_helper"

class Users::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders session transfer and sign-out inside the settings shell" do
    get user_account_url

    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Account"
    assert_select "#session_transfer_label"
    assert_select "form[action=?]", session_path do
      assert_select "input[name=_method][value=delete]"
    end
  end
end
