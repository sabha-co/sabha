require "test_helper"

class Notification::BundleTest < ActiveSupport::TestCase
  setup do
    @user = users(:jason)
    @user.notification_settings&.update!(missed_email_enabled: true, email_frequency: :hourly) ||
      @user.create_notification_settings!(missed_email_enabled: true, email_frequency: :hourly)
  end

  test "User#active_notification_bundle creates a new active bundle when none exists" do
    assert_difference -> { Notification::Bundle.count }, 1 do
      bundle = @user.active_notification_bundle

      assert_equal @user.id, bundle.user_id
      assert bundle.active?
      assert_equal "hourly", bundle.frequency
      assert_in_delta 1.hour.from_now, bundle.ends_at, 5.seconds
    end
  end

  test "User#active_notification_bundle snapshots email_frequency at bundle creation" do
    @user.notification_settings.update!(email_frequency: :daily)
    bundle = @user.active_notification_bundle

    assert_equal "daily", bundle.frequency
    assert_in_delta 24.hours.from_now, bundle.ends_at, 5.seconds
  end

  test "User#active_notification_bundle returns the existing active bundle on subsequent calls" do
    first  = @user.active_notification_bundle
    second = @user.active_notification_bundle

    assert_equal first.id, second.id
  end

  test "User#active_notification_bundle ignores delivered bundles when finding active" do
    delivered = @user.notification_bundles.create!(
      frequency: :hourly,
      starts_at: 2.hours.ago, ends_at: 1.hour.ago, delivered_at: 30.minutes.ago
    )

    fresh = @user.active_notification_bundle

    refute_equal delivered.id, fresh.id
    assert fresh.active?
  end

  test "User#active_notification_bundle ignores canceled bundles when finding active" do
    canceled = @user.notification_bundles.create!(
      frequency: :hourly,
      starts_at: 2.hours.ago, ends_at: 1.hour.ago, canceled_at: 30.minutes.ago
    )

    fresh = @user.active_notification_bundle

    refute_equal canceled.id, fresh.id
    assert fresh.active?
  end

  test "open_notification_bundle! falls back to the existing active bundle on RecordNotUnique" do
    # Simulates a racing transaction that committed first: an active bundle
    # already exists, so the second create! trips the partial unique index.
    # The rescue path re-reads via the association.
    pre = @user.notification_bundles.create!(
      frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )

    bundle = @user.send(:open_notification_bundle!)

    assert_equal pre.id, bundle.id
  end

  test "frequency snapshot defaults to hourly when notification_settings absent" do
    User::NotificationSettings.where(user: @user).delete_all
    @user.reload

    bundle = @user.active_notification_bundle
    assert_equal "hourly", bundle.frequency
  end

  test "cancel! sets canceled_at to a recent timestamp" do
    bundle = @user.active_notification_bundle
    bundle.cancel!

    assert bundle.terminal?
    assert_in_delta Time.current, bundle.reload.canceled_at, 5.seconds
  end

  test "mark_delivered! sets delivered_at to a recent timestamp" do
    bundle = @user.active_notification_bundle
    bundle.mark_delivered!

    assert bundle.terminal?
    assert_in_delta Time.current, bundle.reload.delivered_at, 5.seconds
  end

  test "schedule_delivery enqueues a BundleDeliveryJob with wait_until ends_at" do
    bundle = @user.active_notification_bundle

    assert_enqueued_with(job: Notification::BundleDeliveryJob, args: [ bundle ]) do
      bundle.schedule_delivery
    end
  end

  test "destroying the bundle deletes its items" do
    bundle  = @user.active_notification_bundle
    message = rooms(:designers).messages.create!(body: "hi", creator: users(:david), client_message_id: "bundle_dep_#{SecureRandom.hex(4)}")
    Notification::BundleItem.create!(bundle: bundle, message: message, actor: users(:david), kind: "mention")

    assert_difference -> { Notification::BundleItem.count }, -1 do
      bundle.destroy
    end
  end

  test "partial unique index forbids two active bundles for the same user" do
    @user.notification_bundles.create!(
      frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      @user.notification_bundles.create!(
        frequency: :hourly,
        starts_at: Time.current, ends_at: 1.hour.from_now
      )
    end
  end
end
