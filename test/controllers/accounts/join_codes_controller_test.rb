require "test_helper"

class Accounts::JoinCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create new join code" do
    assert_changes -> { accounts(:signal).reload.join_code } do
      post account_join_code_url
      assert_redirected_to edit_account_url
    end
  end

  test "only administrators can create new join codes" do
    sign_in :jz
    post account_join_code_url
    assert_response :forbidden
  end
end
