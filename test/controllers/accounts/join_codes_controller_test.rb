require "test_helper"

class Accounts::JoinCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create new join code" do
    assert_changes -> { accounts(:signal).join_code.reload.code } do
      post account_join_code_url
      assert_redirected_to account_url
    end
  end

  test "only administrators can create new join codes" do
    sign_in :jz
    post account_join_code_url
    assert_redirected_to root_path
  end

  test "update toggles join code expiration off and back on" do
    join_code = accounts(:signal).join_code
    join_code.update!(expires_at: 30.days.from_now)
    assert join_code.expiring?

    patch account_join_code_url
    assert_redirected_to account_url
    refute join_code.reload.expiring?

    patch account_join_code_url
    assert join_code.reload.expiring?
  end

  test "only administrators can toggle join code expiration" do
    sign_in :jz
    patch account_join_code_url
    assert_redirected_to root_path
  end
end
