require "test_helper"

class Users::NotificationSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @settings = users(:david).notification_settings || users(:david).create_notification_settings!
  end

  test "edit renders the form" do
    get edit_user_notification_settings_url(user_id: "me")
    assert_response :success
    assert_select "form"
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
