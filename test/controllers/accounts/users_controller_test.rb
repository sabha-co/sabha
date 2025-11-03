require "test_helper"

class Accounts::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "update" do
    assert users(:david).administrator?

    put account_user_url(users(:david)), params: { user: { role: "administrator" } }

    assert_redirected_to edit_account_url
    assert users(:david).reload.administrator?
  end

  test "destroy" do
    assert_difference -> { User.active.count }, -1 do
      delete account_user_url(users(:david))
    end

    assert_redirected_to edit_account_url
    assert_nil User.active.find_by(id: users(:david).id)
  end

  test "non-admins cannot perform actions" do
    sign_in :kevin

    put account_user_url(users(:david)), params: { user: { role: "administrator" } }
    assert_response :forbidden

    delete account_user_url(users(:david))
    assert_response :forbidden
  end
end
