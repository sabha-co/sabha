require "test_helper"

class Users::EmailChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @user = users(:david)
  end

  test "destroy cancels the pending email change" do
    @user.update!(unconfirmed_email: "pending@example.com")

    delete user_email_change_url

    assert_redirected_to user_profile_url
    assert_equal "Email change cancelled.", flash[:notice]
    assert_nil @user.reload.unconfirmed_email
  end

  test "destroy is a no-op and does not flash when there is no pending change" do
    assert_nil @user.unconfirmed_email

    delete user_email_change_url

    assert_redirected_to user_profile_url
    assert_nil flash[:notice]
    assert_nil @user.reload.unconfirmed_email
  end
end
