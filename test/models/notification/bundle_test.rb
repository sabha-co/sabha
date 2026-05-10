require "test_helper"

class Notification::BundleTest < ActiveSupport::TestCase
  setup do
    @user = users(:jason)
    @user.notification_settings&.update!(missed_email_enabled: true, email_frequency: :hourly) ||
      @user.create_notification_settings!(missed_email_enabled: true, email_frequency: :hourly)
  end

  test "find_or_create_active_for creates a new active bundle when none exists" do
    assert_difference -> { Notification::Bundle.count }, 1 do
      bundle = Notification::Bundle.find_or_create_active_for(@user)

      assert_equal @user.id, bundle.user_id
      assert bundle.active?
      assert_equal "hourly", bundle.frequency
      assert_in_delta 1.hour.from_now, bundle.ends_at, 5.seconds
    end
  end

  test "find_or_create_active_for snapshots email_frequency at bundle creation" do
    @user.notification_settings.update!(email_frequency: :daily)
    bundle = Notification::Bundle.find_or_create_active_for(@user)

    assert_equal "daily", bundle.frequency
    assert_in_delta 24.hours.from_now, bundle.ends_at, 5.seconds
  end

  test "find_or_create_active_for returns the existing active bundle on subsequent calls" do
    first  = Notification::Bundle.find_or_create_active_for(@user)
    second = Notification::Bundle.find_or_create_active_for(@user)

    assert_equal first.id, second.id
  end

  test "find_or_create_active_for ignores delivered bundles when finding active" do
    delivered = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: 2.hours.ago, ends_at: 1.hour.ago, delivered_at: 30.minutes.ago
    )

    fresh = Notification::Bundle.find_or_create_active_for(@user)

    refute_equal delivered.id, fresh.id
    assert fresh.active?
  end

  test "find_or_create_active_for ignores canceled bundles when finding active" do
    canceled = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: 2.hours.ago, ends_at: 1.hour.ago, canceled_at: 30.minutes.ago
    )

    fresh = Notification::Bundle.find_or_create_active_for(@user)

    refute_equal canceled.id, fresh.id
    assert fresh.active?
  end

  test "find_or_create_active_for retries the read on RecordNotUnique" do
    # Pre-existing active bundle simulates a racing transaction that committed
    # first. Force the initial find_by to miss; the create! that follows then
    # trips the partial unique index, raises RecordNotUnique, and the rescue
    # path re-reads via find_by!.
    pre = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )

    miss = mock("active_miss")
    miss.expects(:find_by).with(user_id: @user.id).returns(nil)
    hit  = mock("active_hit")
    hit.expects(:find_by!).with(user_id: @user.id).returns(pre)

    Notification::Bundle.stubs(:active).returns(miss).then.returns(hit)

    bundle = Notification::Bundle.find_or_create_active_for(@user)
    assert_equal pre.id, bundle.id
  end

  test "frequency snapshot defaults to hourly when notification_settings absent" do
    User::NotificationSettings.where(user: @user).delete_all
    @user.reload

    bundle = Notification::Bundle.find_or_create_active_for(@user)
    assert_equal "hourly", bundle.frequency
  end

  test "active? returns false once delivered_at is set" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.update!(delivered_at: Time.current)

    refute bundle.active?
  end

  test "active? returns false once canceled_at is set" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.update!(canceled_at: Time.current)

    refute bundle.active?
  end

  test "terminal? is true when delivered_at is set" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.update!(delivered_at: Time.current)

    assert bundle.terminal?
  end

  test "terminal? is true when canceled_at is set" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.update!(canceled_at: Time.current)

    assert bundle.terminal?
  end

  test "terminal? is false for an active bundle" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)

    refute bundle.terminal?
  end

  test "cancel! sets canceled_at to a recent timestamp" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.cancel!

    assert bundle.terminal?
    assert_in_delta Time.current, bundle.reload.canceled_at, 5.seconds
  end

  test "mark_delivered! sets delivered_at to a recent timestamp" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)
    bundle.mark_delivered!

    assert bundle.terminal?
    assert_in_delta Time.current, bundle.reload.delivered_at, 5.seconds
  end

  test "schedule_delivery enqueues a BundleDeliveryJob with wait_until ends_at" do
    bundle = Notification::Bundle.find_or_create_active_for(@user)

    assert_enqueued_with(job: Notification::BundleDeliveryJob, args: [ bundle ]) do
      bundle.schedule_delivery
    end
  end

  test "destroying the bundle deletes its items" do
    bundle  = Notification::Bundle.find_or_create_active_for(@user)
    message = rooms(:designers).messages.create!(body: "hi", creator: users(:david), client_message_id: "bundle_dep_#{SecureRandom.hex(4)}")
    Notification::BundleItem.create!(bundle: bundle, message: message, actor: users(:david), kind: "mention")

    assert_difference -> { Notification::BundleItem.count }, -1 do
      bundle.destroy
    end
  end

  test "partial unique index forbids two active bundles for the same user" do
    Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      Notification::Bundle.create!(
        user: @user, frequency: :hourly,
        starts_at: Time.current, ends_at: 1.hour.from_now
      )
    end
  end

  test "partial unique index permits a new active bundle after the previous is delivered" do
    delivered = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: 2.hours.ago, ends_at: 1.hour.ago, delivered_at: Time.current
    )

    assert_nothing_raised do
      Notification::Bundle.create!(
        user: @user, frequency: :hourly,
        starts_at: Time.current, ends_at: 1.hour.from_now
      )
    end
  end
end
