require "test_helper"

class Membership::NotifiableTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:designers)
    @creator = users(:david)
    @recipient_membership = memberships(:jason_designers)
    @message = @room.messages.create!(
      body: "Hello",
      creator: @creator,
      client_message_id: "notifiable_test_#{SecureRandom.hex(4)}"
    )
  end

  # ---------- receives_in_app_row_for? ----------

  test "receives_in_app_row_for? returns true for an active visible member with mention activity" do
    assert @recipient_membership.receives_in_app_row_for?(@message, :mention)
  end

  test "receives_in_app_row_for? returns false for the message creator" do
    creator_membership = memberships(:david_designers)
    assert_equal @creator.id, creator_membership.user_id

    refute creator_membership.receives_in_app_row_for?(@message, :mention)
  end

  test "receives_in_app_row_for? returns false when membership is invisible" do
    @recipient_membership.update!(involvement: :invisible)

    refute @recipient_membership.receives_in_app_row_for?(@message, :mention)
  end

  test "receives_in_app_row_for? returns false for activity types outside IN_APP_ROW_TYPES" do
    refute @recipient_membership.receives_in_app_row_for?(@message, :direct_message)
    refute @recipient_membership.receives_in_app_row_for?(@message, :everyone_room_message)
  end

  test "receives_in_app_row_for? returns false when message is deactivated" do
    @message.deactivate!

    refute @recipient_membership.receives_in_app_row_for?(@message, :mention)
  end

  test "receives_in_app_row_for? returns false when sender is blocked by recipient" do
    @recipient_membership.user.block!(@creator)

    refute @recipient_membership.receives_in_app_row_for?(@message, :mention)
  end

  # ---------- receives_push_for? ----------

  test "receives_push_for? returns false when the membership is connected" do
    @recipient_membership.connected

    refute @recipient_membership.receives_push_for?(@message, :mention)
  end

  test "receives_push_for? returns true for direct_message regardless of involvement" do
    @recipient_membership.disconnected
    @recipient_membership.update!(involvement: :nothing)

    assert @recipient_membership.receives_push_for?(@message, :direct_message)
  end

  test "receives_push_for? returns false for everyone_room_message when involvement is mentions" do
    @recipient_membership.disconnected
    @recipient_membership.update!(involvement: :mentions)

    refute @recipient_membership.receives_push_for?(@message, :everyone_room_message)
  end

  test "receives_push_for? returns true for everyone_room_message when involvement is everything" do
    @recipient_membership.disconnected
    @recipient_membership.update!(involvement: :everything)

    assert @recipient_membership.receives_push_for?(@message, :everyone_room_message)
  end

  test "receives_push_for? returns false when user's push_enabled is off" do
    @recipient_membership.disconnected
    (@recipient_membership.user.notification_settings || @recipient_membership.user.create_notification_settings!).update!(push_enabled: false)

    refute @recipient_membership.receives_push_for?(@message, :mention)
  end

  test "receives_push_for? returns false when sender is blocked by recipient" do
    @recipient_membership.disconnected
    @recipient_membership.user.block!(@creator)

    refute @recipient_membership.receives_push_for?(@message, :mention)
  end

  # ---------- receives_missed_email_for? ----------

  test "receives_missed_email_for? returns false when activity_type is not in EMAIL_TYPES" do
    enable_email_path!

    refute @recipient_membership.receives_missed_email_for?(@message, :everyone_room_message)
    refute @recipient_membership.receives_missed_email_for?(@message, :thread_reply)
    refute @recipient_membership.receives_missed_email_for?(@message, :boost)
  end

  test "receives_missed_email_for? returns true for mention with all gates open" do
    enable_email_path!

    assert @recipient_membership.receives_missed_email_for?(@message, :mention)
  end

  test "receives_missed_email_for? returns true for direct_message with all gates open" do
    enable_email_path!

    assert @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_missed_email_for? returns false when account email_notifications_enabled is off" do
    enable_email_path!
    Current.account.update!(email_notifications_enabled: false)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_missed_email_for? returns false when user's missed_email_enabled is off" do
    enable_email_path!
    @recipient_membership.user.notification_settings.update!(missed_email_enabled: false)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_missed_email_for? returns false when user is not workspace_locally_away" do
    enable_email_path!
    @recipient_membership.update!(connected_at: Time.current)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_missed_email_for? returns false when sender is blocked" do
    enable_email_path!
    @recipient_membership.user.block!(@creator)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
  end

  test "receives_missed_email_for? returns false when message is deactivated" do
    enable_email_path!
    @message.deactivate!

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
  end

  test "receives_missed_email_for? returns false for the message creator" do
    enable_email_path!
    creator_membership = memberships(:david_designers)

    refute creator_membership.receives_missed_email_for?(@message, :mention)
  end

  test "receives_missed_email_for? returns false for :mention when involvement is :nothing" do
    enable_email_path!
    @recipient_membership.update!(involvement: :nothing)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
  end

  test "receives_missed_email_for? returns false for :direct_message when global mode is :nothing" do
    enable_email_path!
    # Per-room :everything beats global mute (effective_involvement rule 1),
    # so we set per-room :mentions to test that the global :nothing kills the DM email.
    @recipient_membership.update!(involvement: :mentions)
    @recipient_membership.user.notification_settings.update!(mode: :nothing)

    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_missed_email_for? returns false when membership is invisible" do
    enable_email_path!
    @recipient_membership.update!(involvement: :invisible)

    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  private
    def enable_email_path!
      Current.account.update!(email_notifications_enabled: true)
      user = @recipient_membership.user
      user.notification_settings&.update!(missed_email_enabled: true) ||
        user.create_notification_settings!(missed_email_enabled: true)
      # Fixtures default connected_at to nil → workspace_locally_away? is true.
    end
end
