require "test_helper"

class User::NotificationSettingsTest < ActiveSupport::TestCase
  test "User.create! synchronously creates a notification_settings row with the documented defaults" do
    user = User.create!(name: "Settings Default", email_address: "settings_default@example.com")

    settings = user.notification_settings
    refute_nil settings, "after_create_commit should have built notification_settings"
    assert_equal "mentions_and_dms", settings.mode
    assert_equal "hourly", settings.email_frequency
    assert_equal true, settings.weekly_digest_subscribed
    assert_equal false, settings.missed_email_enabled
    assert_equal true, settings.push_enabled
    assert_nil settings.last_digest_sent_at
  end

  test "ensure_notification_settings is idempotent — does not raise on the unique index" do
    user = User.create!(name: "Idempotent", email_address: "idempotent@example.com")
    refute_nil user.notification_settings

    # Re-running the callback path must not violate the unique index.
    assert_nothing_raised { user.send(:ensure_notification_settings) }
    assert_equal 1, User::NotificationSettings.where(user_id: user.id).count
  end

  test "user.destroy cleans up the settings row" do
    user = User.create!(name: "Destroyable", email_address: "destroyable@example.com")
    settings_id = user.notification_settings.id

    user.destroy

    assert_nil User::NotificationSettings.find_by(id: settings_id)
  end
end
