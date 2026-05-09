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

  # ---------- receives_missed_email_for? / receives_digest? ----------

  test "receives_missed_email_for? returns false in v1 — settings table not yet present" do
    refute @recipient_membership.receives_missed_email_for?(@message, :mention)
    refute @recipient_membership.receives_missed_email_for?(@message, :direct_message)
  end

  test "receives_digest? returns false in v1 — settings table not yet present" do
    refute @recipient_membership.receives_digest?
  end
end
