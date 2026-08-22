require "test_helper"

class Users::NotificationSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @settings = users(:david).notification_settings || users(:david).create_notification_settings!
    Sabha.stubs(:email_globally_disabled?).returns(false)
  end

  test "edit renders the form" do
    get edit_user_notification_settings_url(user_id: "me")
    assert_response :success
    assert_select "form"
    assert_select ".settings-nav__item[aria-current=page]", text: "Notifications"
  end

  test "edit offers the device-level push enrollment prompt" do
    get edit_user_notification_settings_url(user_id: "me")

    assert_response :success
    assert_select "#notification_bell_container[hidden]" do
      assert_select "button[data-notifications-target=bell]"
    end
  end

  test "edit lists shared memberships with involvement controls" do
    get edit_user_notification_settings_url(user_id: "me")

    assert_response :success
    assert_select "menu li.membership-item", minimum: 1
    users(:david).memberships.shared.each do |membership|
      assert_select "menu li.membership-item a[href=?]", room_path(membership.room)
    end
  end

  test "edit hides missed-email controls when account email_notifications_enabled is off" do
    Account.sole.update!(email_notifications_enabled: false, weekly_digest_enabled: true)

    get edit_user_notification_settings_url(user_id: "me")

    assert_select "input[name='user_notification_settings[missed_email_enabled]']", count: 0
    assert_select "button[name='user_notification_settings[email_frequency]']", count: 0
    assert_match(/Missed-notification email is turned off for this workspace/, @response.body)
  end

  test "edit hides weekly-digest control when account weekly_digest_enabled is off" do
    Account.sole.update!(email_notifications_enabled: true, weekly_digest_enabled: false)

    get edit_user_notification_settings_url(user_id: "me")

    assert_select "input[name='user_notification_settings[weekly_digest_subscribed]']", count: 0
    assert_match(/weekly community digest is turned off for this workspace/, @response.body)
  end

  test "edit collapses to a single message when both account email flags are off" do
    Account.sole.update!(email_notifications_enabled: false, weekly_digest_enabled: false)

    get edit_user_notification_settings_url(user_id: "me")

    assert_match(/Email notifications are turned off for this workspace/, @response.body)
    assert_no_match(/Missed-notification email is turned off/, @response.body)
    assert_no_match(/weekly community digest is turned off/, @response.body)
  end

  test "edit hides the entire email section when email is globally disabled" do
    Account.sole.update!(email_notifications_enabled: true, weekly_digest_enabled: true)
    Sabha.stubs(:email_globally_disabled?).returns(true)

    get edit_user_notification_settings_url(user_id: "me")

    assert_select ".settings-label", text: "Email", count: 0
    assert_select "input[name='user_notification_settings[missed_email_enabled]']", count: 0
    assert_select "input[name='user_notification_settings[weekly_digest_subscribed]']", count: 0
  end

  test "edit shows admin link when account flags are off and current user is administrator" do
    Account.sole.update!(email_notifications_enabled: false, weekly_digest_enabled: false)

    get edit_user_notification_settings_url(user_id: "me")

    assert_select "a[href=?]", edit_account_path, minimum: 1
  end

  test "edit hides the email fieldset from non-admins when both account flags are off" do
    Account.sole.update!(email_notifications_enabled: false, weekly_digest_enabled: false)
    sign_in :jz

    get edit_user_notification_settings_url(user_id: "me")

    assert_select "a[href=?]", edit_account_path, count: 0
    assert_select ".settings-label", text: "Email", count: 0
    assert_no_match(/Missed-notification email is turned off/, @response.body)
    assert_no_match(/weekly community digest is turned off/, @response.body)
  end

  test "edit keeps the email fieldset for non-admins when at least one feature is on" do
    Account.sole.update!(email_notifications_enabled: true, weekly_digest_enabled: false)
    sign_in :jz

    get edit_user_notification_settings_url(user_id: "me")

    assert_select ".settings-label", text: "Email", count: 1
    assert_select "input[name='user_notification_settings[missed_email_enabled]']", count: 1
    assert_select "input[name='user_notification_settings[weekly_digest_subscribed]']", count: 0
    assert_no_match(/weekly community digest is turned off/, @response.body)
  end

  test "edit shows missed-email and digest controls when both account flags are on" do
    Account.sole.update!(email_notifications_enabled: true, weekly_digest_enabled: true)

    get edit_user_notification_settings_url(user_id: "me")

    assert_select "input[name='user_notification_settings[missed_email_enabled]']", count: 1
    assert_select "button[name='user_notification_settings[email_frequency]']", count: 2
    assert_select "button[name='user_notification_settings[email_frequency]'][value=hourly]"
    assert_select "button[name='user_notification_settings[email_frequency]'][value=daily]"
    assert_select "input[name='user_notification_settings[weekly_digest_subscribed]']", count: 1
  end

  test "update flips missed_email_enabled" do
    @settings.update!(missed_email_enabled: false)

    patch user_notification_settings_url(user_id: "me"),
      params: { user_notification_settings: { missed_email_enabled: "1" } }

    assert_redirected_to edit_user_notification_settings_url(user_id: "me")
    assert @settings.reload.missed_email_enabled
  end

  test "update changes email_frequency" do
    patch user_notification_settings_url(user_id: "me"),
      params: { user_notification_settings: { email_frequency: "daily" } }

    assert_equal "daily", @settings.reload.email_frequency
  end

  test "update flips weekly_digest_subscribed off" do
    @settings.update!(weekly_digest_subscribed: true)

    patch user_notification_settings_url(user_id: "me"),
      params: { user_notification_settings: { weekly_digest_subscribed: "0" } }

    refute @settings.reload.weekly_digest_subscribed
  end

  test "update rejects unknown attributes" do
    @settings.update!(missed_email_enabled: false)
    last_digest = @settings.last_digest_sent_at

    patch user_notification_settings_url(user_id: "me"),
      params: { user_notification_settings: { missed_email_enabled: "1", last_digest_sent_at: 1.year.ago } }

    if last_digest.nil?
      assert_nil @settings.reload.last_digest_sent_at
    else
      assert_equal last_digest, @settings.reload.last_digest_sent_at
    end
  end

  test "creates the settings row lazily if missing" do
    @settings.destroy

    get edit_user_notification_settings_url(user_id: "me")
    assert_response :success
    refute_nil users(:david).reload.notification_settings
  end

  test "requires authentication" do
    delete session_url
    get edit_user_notification_settings_url(user_id: "me")
    assert_response :redirect
  end
end
