require "test_helper"

# The @everyone guardrail (U7): above the configured member ceiling, @everyone
# keeps its durable in-app surfaces (Activity rows + mention badge) but stops
# fanning out per-member push, email, and live broadcasts — it posts room-wide
# instead. The admin/open floor is unchanged and covered in message_test.
class Message::EveryoneCapTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @room = rooms(:pets)      # Rooms::Open, members: david + jason (both admins)
    @admin = users(:jason)
    @recipient = users(:david)
  end

  test "everyone_mention_over_ceiling? tracks the configured ceiling" do
    with_everyone_ceiling(1) { assert @room.everyone_mention_over_ceiling? }
    with_everyone_ceiling(1000) { assert_not @room.everyone_mention_over_ceiling? }
  end

  test "a capped @everyone still writes the Activity row and bumps the mention badge" do
    with_everyone_ceiling(1) do
      membership = @room.memberships.find_by(user: @recipient)
      force_all_unread(membership)

      assert_difference -> { Notification.where(activity_type: "mention", user_id: @recipient.id).count }, 1 do
        assert_difference -> { membership.reload.unread_notifications_count }, 1 do
          post_everyone("capped_durable")
        end
      end
    end
  end

  test "a capped @everyone drops the :mention activity type so push and email do not fan out" do
    with_everyone_ceiling(1) do
      message = post_everyone("capped_types")

      assert_equal [ :everyone_room_message ], @room.applicable_activity_types(message)
    end
  end

  test "a capped @everyone skips the per-recipient Activity append and live badge broadcasts" do
    with_everyone_ceiling(1) do
      message = nil
      assert_no_enqueued_jobs only: BroadcastMentionNotificationsJob do
        message = post_everyone("capped_broadcasts")
      end

      badge_stream = UnreadNotificationsChannel.broadcasting_for(@recipient)
      assert_no_broadcasts badge_stream do
        assert_no_enqueued_jobs only: BroadcastUnreadNotificationsJob do
          message.broadcast_notifications
        end
      end
    end
  end

  test "below the ceiling @everyone still fans out as a mention" do
    with_everyone_ceiling(1000) do
      message = nil
      assert_enqueued_with job: BroadcastMentionNotificationsJob do
        message = post_everyone("uncapped_fanout")
      end

      badge_stream = UnreadNotificationsChannel.broadcasting_for(@recipient)
      assert_broadcasts badge_stream, 1 do
        perform_enqueued_jobs only: BroadcastUnreadNotificationsJob do
          message.broadcast_notifications
        end
      end

      assert_includes @room.applicable_activity_types(message), :mention
    end
  end

  private
    def post_everyone(client_message_id)
      sgid = Everyone.new.attachable_sgid
      body = %(<div><action-text-attachment sgid="#{sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment></div>)
      @room.messages.create!(body: body, creator: @admin, client_message_id: client_message_id)
    end

    def with_everyone_ceiling(value)
      original = Rails.configuration.x.everyone_mention.ceiling
      Rails.configuration.x.everyone_mention.ceiling = value
      yield
    ensure
      Rails.configuration.x.everyone_mention.ceiling = original
    end
end
