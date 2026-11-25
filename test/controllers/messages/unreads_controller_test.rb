require "test_helper"

class Messages::UnreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @channel = channels(:watercooler)
    @message = @channel.messages.create!(creator: users(:jason), body: "Test message")
    @membership = @channel.memberships.find_by(user: users(:david))
    catch_up @membership
  end

  test "create marks message as unread" do
    assert @membership.read?

    post channel_message_unreads_url(@channel, @message, format: :turbo_stream)

    assert_response :success
    @membership.reload
    assert @membership.unread?
    assert_equal @message, @membership.first_unread_message
  end

  test "create pushes the unread state to the member's own devices via ReadChannelsChannel" do
    # Mark-as-unread is per-user state, so it rides the per-user read-state
    # channel (the inverse of its read broadcasts) — not the shared channel-list
    # stream, which would nudge the whole account for one member's action.
    payloads = capture_broadcasts(ReadChannelsChannel.broadcasting_for(users(:david))) do
      assert_no_broadcasts Account.sole.channel_list_stream_name do
        post channel_message_unreads_url(@channel, @message, format: :turbo_stream)
      end
    end

    assert_equal 1, payloads.size
    payload = payloads.first
    assert payload["unread"], "the payload distinguishes mark-as-unread from a read broadcast"
    assert_equal @channel.id, payload["channel_id"]
    assert_equal @channel.reload.messages_count, payload["channel_size"]
    assert_equal @channel.last_active_at.iso8601, payload["channel_updated_at"]
  end
end
