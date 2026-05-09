require "test_helper"
require Rails.root.join("db/migrate/20260509180101_backfill_user_notification_settings")

class User::NotificationSettingsTest < ActiveSupport::TestCase
  test "User.create! synchronously creates a notification_settings row with arch § 12 defaults" do
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

  test "weekly_digest_subscribed defaults to true (member opt-out per PRD § Product principles #6)" do
    user = User.create!(name: "Digest Default", email_address: "digest_default@example.com")

    assert_equal true, user.notification_settings.weekly_digest_subscribed,
      "Members must default to subscribed so admin-enabled digest reaches existing membership immediately"
  end

  test "missed_email_enabled defaults to false (opt-in for personal mail)" do
    user = User.create!(name: "Email Default", email_address: "email_default@example.com")

    refute user.notification_settings.missed_email_enabled
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

  test "mode enum exposes prefixed predicates" do
    user = User.create!(name: "Mode Predicates", email_address: "mode_predicates@example.com")

    assert user.notification_settings.mode_mentions_and_dms?
    refute user.notification_settings.mode_nothing?
    refute user.notification_settings.mode_all?
  end

  test "email_frequency enum exposes prefixed predicates" do
    user = User.create!(name: "Freq Predicates", email_address: "freq_predicates@example.com")

    assert user.notification_settings.email_frequency_hourly?
    refute user.notification_settings.email_frequency_daily?
  end

  test "backfill creates settings rows only for users that don't yet have one" do
    # Fixtures bypass the after_create_commit callback, so legacy users have no row.
    legacy_user = users(:david)
    legacy_user.notification_settings&.destroy
    assert_nil legacy_user.reload.notification_settings

    seeded_user = User.create!(name: "Pre-seeded", email_address: "pre_seeded@example.com")
    refute_nil seeded_user.notification_settings, "callback should have seeded this user"

    # Re-run the same INSERT-WHERE-NOT-EXISTS the migration uses.
    BackfillUserNotificationSettings.new.up

    legacy_user.reload
    refute_nil legacy_user.notification_settings, "backfill must seed the legacy user"
    assert_equal "mentions_and_dms", legacy_user.notification_settings.mode
    assert_equal true, legacy_user.notification_settings.weekly_digest_subscribed

    # The pre-seeded user must still have exactly one row — no duplicates.
    assert_equal 1, User::NotificationSettings.where(user_id: seeded_user.id).count
  end
end
