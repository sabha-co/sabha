require "test_helper"

class Room::DesktopNotificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = rooms(:david_and_jason)
    @sender = users(:david)
    @recipient = users(:jason)
  end

  test "eligible DM emits one desktop event for the recipient and none for the sender" do
    Desktop::NotificationEvent.expects(:deliver_for).with(
      has_entries(message: kind_of(Message), user: @recipient, activity_types: [ :direct_message ])
    ).once

    perform_enqueued_jobs only: Notification::DispatchJob do
      @room.messages.create!(
        body: "Background DM",
        creator: @sender,
        client_message_id: "desktop_dm_recipient"
      )
    end
  end

  test "mention inside a direct message collapses to one desktop event" do
    Desktop::NotificationEvent.expects(:deliver_for).with(
      has_entries(user: @recipient, activity_types: [ :direct_message, :mention ])
    ).once

    perform_enqueued_jobs only: Notification::DispatchJob do
      @room.messages.create!(
        body: "Hey #{mention_attachment_for(:jason)}",
        creator: @sender,
        client_message_id: "desktop_dm_mention_collapse"
      )
    end
  end

  test "push-disabled recipient receives no desktop event" do
    settings = @recipient.notification_settings || @recipient.create_notification_settings!
    settings.update!(push_enabled: false)

    Desktop::NotificationEvent.expects(:deliver_for).never

    perform_enqueued_jobs only: Notification::DispatchJob do
      @room.messages.create!(
        body: "Muted desktop path",
        creator: @sender,
        client_message_id: "desktop_push_disabled"
      )
    end
  end

  test "member watching the room receives no desktop event" do
    watching @room, @recipient

    Desktop::NotificationEvent.expects(:deliver_for).never

    perform_enqueued_jobs only: Notification::DispatchJob do
      @room.messages.create!(
        body: "Focused room",
        creator: @sender,
        client_message_id: "desktop_focused_room"
      )
    end
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
end
