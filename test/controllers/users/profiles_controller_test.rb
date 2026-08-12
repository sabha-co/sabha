require "test_helper"

class Users::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @user = users(:david)
  end

  test "show" do
    get user_profile_url

    assert_response :success
  end

  test "show links to notification preferences" do
    get user_profile_url

    assert_select "a[href=?]", edit_user_notification_settings_path, count: 1
  end

  test "status message saves from the profile form and is distinct from bio" do
    patch user_profile_url, params: {
      user: { status_message: "Gardening this week", bio: "Long-time member" }
    }

    assert_redirected_to user_profile_url
    @user.reload
    assert_equal "Gardening this week", @user.status_message
    assert_equal "Long-time member", @user.bio
  end

  test "email change sends verification email" do
    assert_enqueued_emails 1 do
      patch user_profile_url, params: {
        user: { email_address: "newemail@example.com" }
      }
    end

    assert_redirected_to user_profile_url
    assert_match "verification email has been sent", flash[:notice]
    assert_equal "newemail@example.com", @user.reload.unconfirmed_email
    assert_equal "david@37signals.com", @user.email_address # Original email unchanged
  end

  test "show displays pending email change" do
    @user.update!(unconfirmed_email: "pending@example.com")

    get user_profile_url

    assert_response :success
    assert_select "strong", "pending@example.com"
  end

  test "email with different case does not trigger change flow" do
    # david@37signals.com -> David@37signals.com should not trigger email change
    assert_no_enqueued_emails do
      patch user_profile_url, params: {
        user: { email_address: "David@37signals.com", name: "David Updated" }
      }
    end

    assert_redirected_to user_profile_url
    assert_nil @user.reload.unconfirmed_email
    assert_equal "David Updated", @user.name
  end

  test "invalid email format shows error instead of 500" do
    patch user_profile_url, params: {
      user: { email_address: "not-an-email" }
    }

    assert_redirected_to user_profile_url
    assert_match "invalid", flash[:alert].downcase
    assert_nil @user.reload.unconfirmed_email
  end
end
