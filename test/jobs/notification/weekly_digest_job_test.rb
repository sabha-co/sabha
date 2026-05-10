require "test_helper"

class Notification::WeeklyDigestJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user  = users(:jason)
    @actor = users(:david)
    @room  = rooms(:designers)

    @user.notification_settings || @user.create_notification_settings!
    @user.notification_settings.update!(weekly_digest_subscribed: true, last_digest_sent_at: nil)
    Account.sole.update!(weekly_digest_enabled: true)
  end

  test "skips entirely when account.weekly_digest_enabled is false" do
    Account.sole.update!(weekly_digest_enabled: false)
    seed_active_room_messages

    assert_no_emails do
      Notification::WeeklyDigestJob.perform_now
    end
    assert_nil @user.notification_settings.reload.last_digest_sent_at
  end

  test "delivers when subscribed user has qualifying activity and stamps last_digest_sent_at" do
    seed_active_room_messages

    travel_to Time.current do
      assert_emails 1 do
        Notification::WeeklyDigestJob.perform_now
      end
      assert_in_delta Time.current.to_f, @user.notification_settings.reload.last_digest_sent_at.to_f, 2
    end
  end

  test "skips user with last_digest_sent_at within 6 days (dedup)" do
    seed_active_room_messages
    @user.notification_settings.update!(last_digest_sent_at: 3.days.ago)
    last = @user.notification_settings.last_digest_sent_at

    assert_no_emails do
      Notification::WeeklyDigestJob.perform_now
    end
    assert_equal last, @user.notification_settings.reload.last_digest_sent_at
  end

  test "skips empty content without stamping last_digest_sent_at" do
    # No messages in the past week → empty content
    Message.update_all(created_at: 30.days.ago)

    assert_no_emails do
      Notification::WeeklyDigestJob.perform_now
    end
    assert_nil @user.notification_settings.reload.last_digest_sent_at
  end

  test "skips bots, deactivated, banned, and unverified users" do
    seed_active_room_messages

    bot = User.create!(name: "Digest Bot", role: :bot, bot_token: User.generate_bot_token)
    bot.notification_settings.update!(weekly_digest_subscribed: true)
    deactivated = User.create!(name: "Gone", email_address: "gone@example.com", password_digest: "x", verified_at: 1.day.ago)
    deactivated.update!(status: :deactivated)
    deactivated.notification_settings.update!(weekly_digest_subscribed: true)
    unverified = User.create!(name: "New", email_address: "new@example.com", password_digest: "x")
    unverified.notification_settings.update!(weekly_digest_subscribed: true)

    Notification::WeeklyDigestJob.perform_now

    [ bot, deactivated, unverified ].each do |user|
      assert_nil user.notification_settings.reload.last_digest_sent_at,
        "#{user.name} should not have received a digest"
    end
  end

  test "skips users with weekly_digest_subscribed: false" do
    seed_active_room_messages
    @user.notification_settings.update!(weekly_digest_subscribed: false)

    assert_no_emails do
      Notification::WeeklyDigestJob.perform_now
    end
  end

  test "GC deletes terminal bundles older than 90 days at the top of the run" do
    Account.sole.update!(weekly_digest_enabled: false) # isolate GC behavior
    old_delivered = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: 100.days.ago, ends_at: 100.days.ago + 1.hour,
      delivered_at: 95.days.ago
    )
    old_delivered.update_column(:updated_at, 95.days.ago)

    fresh_delivered = Notification::Bundle.create!(
      user: @actor, frequency: :hourly,
      starts_at: 1.day.ago, ends_at: Time.current,
      delivered_at: 1.day.ago
    )

    Notification::WeeklyDigestJob.perform_now

    refute Notification::Bundle.exists?(old_delivered.id), "old terminal bundle should be pruned"
    assert Notification::Bundle.exists?(fresh_delivered.id), "fresh terminal bundle should remain"
  end

  test "GC does not delete active bundles regardless of age" do
    Account.sole.update!(weekly_digest_enabled: false)
    ancient_active = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: 200.days.ago, ends_at: 200.days.ago + 1.hour
    )
    ancient_active.update_column(:updated_at, 200.days.ago)

    Notification::WeeklyDigestJob.perform_now

    assert Notification::Bundle.exists?(ancient_active.id), "active bundles must never be pruned"
  end

  private
    def seed_active_room_messages
      # Three messages in @room within the past week so the room qualifies as
      # "recently active" (>= ACTIVE_ROOM_MIN_MESSAGES = 3).
      3.times do |i|
        @room.messages.create!(
          body: "<div>Hi there #{i}</div>",
          creator: @actor,
          client_message_id: "digest_seed_#{i}_#{SecureRandom.hex(4)}"
        )
      end
    end
end
