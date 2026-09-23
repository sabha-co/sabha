require "test_helper"

class Room::DesktopNotificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, ActionCable::TestHelper

  setup do
    @room = rooms(:david_and_jason)
    @sender = users(:david)
    @recipient = users(:jason)
  end

  test "eligible DM emits one desktop event for the recipient and none for the sender" do
    events = capture_broadcasts(desktop_stream(@recipient)) do
      assert_no_broadcasts(desktop_stream(@sender)) do
        send_dm "Background DM", client_message_id: "desktop_dm_recipient"
      end
    end

    assert_equal 1, events.size
    assert_equal [ "direct_message" ], events.first["activity_types"]
  end

  test "mention inside a direct message collapses to one desktop event" do
    events = capture_broadcasts(desktop_stream(@recipient)) do
      send_dm "Hey #{mention_attachment_for(:jason)}", client_message_id: "desktop_dm_mention_collapse"
    end

    assert_equal 1, events.size
    assert_equal [ "direct_message", "mention" ], events.first["activity_types"]
  end

  test "push-disabled recipient receives no desktop event" do
    settings = @recipient.notification_settings || @recipient.create_notification_settings!
    settings.update!(push_enabled: false)

    assert_no_broadcasts(desktop_stream(@recipient)) do
      send_dm "Muted desktop path", client_message_id: "desktop_push_disabled"
    end
  end

  test "member watching the room receives no desktop event" do
    watching @room, @recipient

    assert_no_broadcasts(desktop_stream(@recipient)) do
      send_dm "Focused room", client_message_id: "desktop_focused_room"
    end
  end

  test "nothing is computed or sent while desktop notifications are off" do
    Desktop.stubs(:notifications_enabled?).returns(false)
    Desktop::NotificationEvent.expects(:new).never

    assert_no_broadcasts(desktop_stream(@recipient)) do
      send_dm "Flag off", client_message_id: "desktop_flag_off"
    end
  end

  test "a failed desktop broadcast still delivers web pushes and does not fail the job" do
    DesktopChannel.stubs(:broadcast_to_user).raises(RuntimeError, "cable down")
    Message.any_instance.expects(:deliver_pushes_to).once

    send_dm "Push survives", client_message_id: "desktop_broadcast_failure"
  end

  test "thread reply keeps the existing push path shape" do
    parent = rooms(:designers).messages.create!(
      body: "Parent for desktop thread",
      creator: @sender,
      client_message_id: "desktop_thread_parent"
    )
    thread = parent.threads.create!(creator: @sender)
    message = thread.messages.create!(
      body: "Reply body",
      creator: @sender,
      client_message_id: "desktop_thread_reply"
    )

    payload = Room::MessagePusher.payload_for(room: thread, message: message)
    event = Desktop::NotificationEvent.new(
      message: message,
      user: users(:kevin),
      activity_types: [ :thread_reply ]
    )

    assert_equal payload[:path], event.as_json[:path]
  end

  private
    def desktop_stream(user)
      DesktopChannel.broadcasting_for(user)
    end

    def send_dm(body, client_message_id:)
      perform_enqueued_jobs only: Notification::DispatchJob do
        @room.messages.create!(body: body, creator: @sender, client_message_id: client_message_id)
      end
    end
end
