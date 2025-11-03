require "test_helper"

class Accounts::CustomStylesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "edit" do
    get edit_account_custom_styles_url
    assert_response :ok
  end

  test "update" do
    assert users(:david).administrator?

    put account_custom_styles_url, params: { account: { custom_styles: ":root { --color-text: red; }" } }

    assert_redirected_to edit_account_custom_styles_url
    assert_equal accounts(:signal).custom_styles, ":root { --color-text: red; }"
  end

  test "non-admins cannot update" do
    sign_in :kevin
    assert users(:kevin).member?

    put account_custom_styles_url, params: { account: { custom_styles: ":root { --color-text: red; }" } }
    assert_response :forbidden
  end
end
