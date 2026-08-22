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

  test "show renders inside the settings shell with Profile current" do
    get user_profile_url

    assert_select ".settings-nav__item", count: 5
    assert_select ".settings-nav__item[aria-current=page]", text: "Profile"
  end

  test "admins get the community settings switch" do
    get user_profile_url

    assert_select "a.settings-nav__switch[href=?]", edit_account_path, text: /Community settings/
  end

  test "non-admins see their email and get no community settings switch" do
    sign_in :kevin

    get user_profile_url

    assert_response :success
    assert_select "input[value=?]", users(:kevin).email_address
    assert_select ".settings-nav__switch", count: 0
  end

  test "the theme control moved off the profile page" do
    get user_profile_url

    assert_select "[data-action*=?]", "theme#setLight", count: 0
  end

  test "profile fields are grouped into labelled sections" do
    get user_profile_url

    %w[ Identity About Links ].each do |heading|
      assert_select ".settings-group__heading", text: heading
    end
    assert_select ".settings-fields", minimum: 2
  end

  test "show renders the Links group with its hint" do
    get user_profile_url

    assert_select ".settings-group__heading", text: "Links"
    assert_select ".settings-field__hint", text: /full address/, count: 1
  end

  test "the password field is not on the profile page" do
    get user_profile_url

    assert_select ".settings-group__heading", text: "Password", count: 0
    assert_select "input[type=password]", count: 0
  end

  test "optional profile fields can be cleared" do
    @user.update!(status_message: "Working", personal_url: "https://example.com")

    patch user_profile_url, params: { user: { status_message: "", personal_url: "" } }

    assert_redirected_to user_profile_url
    assert_equal "", @user.reload.status_message
    assert_equal "", @user.personal_url
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
