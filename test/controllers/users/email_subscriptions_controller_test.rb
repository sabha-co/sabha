require "test_helper"

class Users::EmailSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @user = users(:david)
  end

  test "show renders subscription status" do
    get email_subscription_url
    assert_response :success
  end

  test "toggles from unsubscribed to subscribed" do
    @user.unsubscribe_from_emails

    put email_subscription_url

    assert_redirected_to email_subscription_url
    assert @user.reload.subscribed_to_emails?
  end

  test "toggles from subscribed to unsubscribed" do
    @user.subscribe_to_emails

    put email_subscription_url

    assert_redirected_to email_subscription_url
    assert_not @user.reload.subscribed_to_emails?
  end

  test "requires authentication" do
    delete session_url

    get email_subscription_url

    assert_redirected_to new_session_url
  end
end
