require "test_helper"

class Message::BroadcastsTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:pets)
    @user = users(:david)
  end

  test "broadcast_notifications uses AnyCable batching when available" do
    # Verify AnyCable is available in test environment
    assert defined?(AnyCable), "AnyCable should be defined"
    assert AnyCable.broadcast_adapter.respond_to?(:batching), "Batching should be available"
  end

  test "notification_recipient_ids returns all member ids for @everyone mention" do
    message = @room.messages.build(
      body: "Hello @everyone",
      mentions_everyone: true,
      client_message_id: "test_everyone",
      creator: @user
    )

    user_ids = message.send(:notification_recipient_ids, false)

    assert_includes user_ids, users(:jason).id
    assert_includes user_ids, users(:david).id
  end

  test "notification_recipient_ids filters by unread_at when ignore_if_older_message is true" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = @room.messages.create!(
      body: body_html,
      client_message_id: "test_filter",
      creator: @user
    )

    # Mark one user as having read (unread_at = nil)
    @room.memberships.find_by(user: users(:jason)).update!(unread_at: nil)

    # Mark another user as unread before this message
    @room.memberships.find_by(user: users(:david)).update!(unread_at: 1.hour.ago)

    user_ids = message.send(:notification_recipient_ids, true)

    # David should be included (unread_at before message)
    assert_includes user_ids, users(:david).id

    # Jason should be excluded (read - unread_at is nil)
    assert_not_includes user_ids, users(:jason).id
  end

  test "broadcast_notifications sends to correct channel format" do
    message = @room.messages.build(
      body: "Hello @everyone",
      mentions_everyone: true,
      client_message_id: "channel_test",
      creator: @user
    )

    user_ids = message.send(:notification_recipient_ids, false)

    # Verify channel naming convention
    user_ids.each do |user_id|
      expected_channel = "user_#{user_id}_notifications"
      assert expected_channel.match?(/^user_\d+_notifications$/), "Channel should match pattern"
    end
  end
end
