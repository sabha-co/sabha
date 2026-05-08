require "test_helper"

# Locks today's recipient behavior before the unified notification dispatcher
# refactor. These tests assert exact recipients, not just notification counts,
# so routing drift is caught before push/in-app/thread/boost paths move.
class NotificationRoutingParityTest < ActiveSupport::TestCase
  test "push recipients for regular room messages are disconnected everything members except the creator" do
    message = rooms(:designers).messages.create!(
      body: "Status update",
      creator: users(:david),
      client_message_id: "routing_push_regular"
    )

    assert_equal user_ids(:jason, :jz), queued_push_user_ids_for(message)
  end

  test "push recipients for named mentions include everything members and mentioned mentions members" do
    message = rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: users(:david),
      client_message_id: "routing_push_named_mention"
    )

    assert_equal user_ids(:jason, :jz, :kevin), queued_push_user_ids_for(message)
  end

  test "push recipients do not duplicate everything members who are mentioned" do
    message = rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: users(:david),
      client_message_id: "routing_push_no_duplicate_everything"
    )

    assert_equal user_ids(:jason, :jz), queued_push_user_ids_for(message)
  end

  test "push recipients skip connected memberships" do
    memberships(:kevin_designers).connected

    message = rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: users(:david),
      client_message_id: "routing_push_skip_connected"
    )

    assert_equal user_ids(:jason, :jz), queued_push_user_ids_for(message)
  end

  test "push payload for shared rooms preserves title body and path" do
    message = rooms(:designers).messages.create!(
      body: "Design update",
      creator: users(:david),
      client_message_id: "routing_payload_shared"
    )

    payload = push_payload_for(message)

    assert_equal rooms(:designers).display_name, payload[:title]
    assert_equal "David: Design update", payload[:body]
    assert_equal Rails.application.routes.url_helpers.room_path(rooms(:designers)), payload[:path]
  end

  test "push payload for direct rooms preserves sender title body and room path" do
    message = rooms(:david_and_jason).messages.create!(
      body: "Direct update",
      creator: users(:jason),
      client_message_id: "routing_payload_direct"
    )

    payload = push_payload_for(message)

    assert_equal "Jason", payload[:title]
    assert_equal "Direct update", payload[:body]
    assert_equal Rails.application.routes.url_helpers.room_path(rooms(:david_and_jason)), payload[:path]
  end

  test "push payload for thread replies points back to the parent message" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent for push",
      creator: users(:david),
      client_message_id: "routing_payload_thread_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])
    reply = thread.messages.create!(
      body: "Thread reply for push",
      creator: users(:jason),
      client_message_id: "routing_payload_thread_reply"
    )

    payload = push_payload_for(reply)

    assert_equal Rails.application.routes.url_helpers.room_at_message_path(parent.room, parent), payload[:path]
  end

  test "mention activity rows are broader than push recipients" do
    memberships(:kevin_designers).update!(involvement: "invisible")

    message = rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: users(:david),
      client_message_id: "routing_rows_broader_than_push"
    )

    assert_equal user_ids(:kevin), notification_user_ids(message, "mention")
    assert_equal user_ids(:jason, :jz), queued_push_user_ids_for(message)
  end

  test "@everyone creates mention rows for every non-creator room member" do
    message = rooms(:hq).messages.create!(
      body: everyone_body,
      creator: users(:david),
      client_message_id: "routing_everyone_rows"
    )

    assert_equal user_ids(:jason, :jz, :kevin), notification_user_ids(message, "mention")
  end

  test "direct messages create no activity rows" do
    message = rooms(:david_and_jason).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "routing_direct_no_rows"
    )

    assert_empty notification_user_ids(message, "mention")
  end

  test "mention activity rows broadcast to the recipient inbox activity stream" do
    message = rooms(:pets).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "routing_mention_broadcast"
    )

    assert_turbo_stream_broadcasts [ users(:david), :inbox_activity ], count: 1 do
      BroadcastMentionNotificationsJob.perform_now(message_id: message.id)
    end
  end

  test "thread replies notify visible thread members and parent-room everything members exactly once" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent",
      creator: users(:jason),
      client_message_id: "routing_thread_parent"
    )
    rooms(:pets).memberships.grant_to(users(:kevin))
    rooms(:pets).memberships.find_by(user: users(:kevin)).update!(involvement: "everything")

    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:jason))
    thread.memberships.grant_to([ users(:david), users(:jz) ])
    thread.memberships.find_by(user: users(:david)).update!(involvement: "mentions")
    thread.memberships.find_by(user: users(:jz)).update!(involvement: "mentions")

    reply = thread.messages.create!(
      body: "<div>Replying with #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "routing_thread_reply"
    )

    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: users(:jason).id
    )

    assert_equal user_ids(:jz, :kevin), notification_user_ids(reply, "thread_reply")
  end

  test "creating a thread reply enqueues legacy thread reply notification work" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent for enqueue",
      creator: users(:david),
      client_message_id: "routing_thread_enqueue_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])

    assert_enqueued_jobs 1, only: CreateThreadReplyNotificationsJob do
      thread.messages.create!(
        body: "Thread reply enqueues work",
        creator: users(:jason),
        client_message_id: "routing_thread_enqueue_reply"
      )
    end
  end

  test "thread reply activity rows broadcast to recipient inbox activity streams" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent for broadcast",
      creator: users(:jason),
      client_message_id: "routing_thread_broadcast_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:jason))
    thread.memberships.grant_to(users(:david))
    thread.memberships.find_by(user: users(:david)).update!(involvement: "mentions")
    reply = thread.messages.create!(
      body: "Thread reply broadcast",
      creator: users(:jason),
      client_message_id: "routing_thread_broadcast_reply"
    )

    assert_turbo_stream_broadcasts [ users(:david), :inbox_activity ], count: 1 do
      CreateThreadReplyNotificationsJob.perform_now(
        message_id: reply.id,
        thread_id: thread.id,
        creator_id: users(:jason).id
      )
    end
  end

  test "thread replies under direct messages create no activity rows" do
    parent = rooms(:david_and_jason).messages.create!(
      body: "DM thread parent",
      creator: users(:david),
      client_message_id: "routing_dm_thread_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])

    reply = thread.messages.create!(
      body: "DM thread reply",
      creator: users(:jason),
      client_message_id: "routing_dm_thread_reply"
    )

    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: users(:jason).id
    )

    assert_empty notification_user_ids(reply, "thread_reply")
  end

  test "boosts notify original author only and skip self boosts" do
    message = rooms(:pets).messages.create!(
      body: "Boost target",
      creator: users(:david),
      client_message_id: "routing_boost_target"
    )

    boost = message.boosts.create!(content: "Yes", booster: users(:jason))
    message.boosts.create!(content: "Self", booster: users(:david))

    assert_equal user_ids(:david), notification_user_ids(message, "boost")
    assert_equal users(:jason).id, Notification.find_by(boost_id: boost.id).actor_id
  end

  test "boost activity rows broadcast to the original author inbox activity stream" do
    message = rooms(:pets).messages.create!(
      body: "Boost broadcast target",
      creator: users(:david),
      client_message_id: "routing_boost_broadcast_target"
    )

    assert_turbo_stream_broadcasts [ users(:david), :inbox_activity ], count: 1 do
      message.boosts.create!(content: "Broadcast boost", booster: users(:jason))
    end
  end

  test "boosts in direct message contexts create no activity rows" do
    direct_message = rooms(:david_and_jason).messages.create!(
      body: "DM boost target",
      creator: users(:david),
      client_message_id: "routing_dm_boost_target"
    )
    direct_message.boosts.create!(content: "DM boost", booster: users(:jason))

    parent = rooms(:david_and_jason).messages.create!(
      body: "DM thread boost parent",
      creator: users(:david),
      client_message_id: "routing_dm_thread_boost_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])
    thread_message = thread.messages.create!(
      body: "DM thread boost target",
      creator: users(:david),
      client_message_id: "routing_dm_thread_boost_target"
    )
    thread_message.boosts.create!(content: "Thread boost", booster: users(:jason))

    assert_empty notification_user_ids(direct_message, "boost")
    assert_empty notification_user_ids(thread_message, "boost")
  end

  test "current block behavior still allows non-direct mention rows push and unread counters" do
    users(:david).block!(users(:jason))
    membership = memberships(:david_pets)
    membership.update!(unread_at: 1.day.ago, unread_notifications_count: 0)

    message = rooms(:pets).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "routing_block_baseline"
    )

    assert_equal user_ids(:david), notification_user_ids(message, "mention")
    assert_includes queued_push_user_ids_for(message), users(:david).id
    assert_equal 1, membership.reload.unread_notifications_count
  end

  test "unread notification counters remain synchronous on the legacy path" do
    membership = memberships(:kevin_designers)
    membership.update!(unread_at: 1.day.ago, unread_notifications_count: 0)

    rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: users(:david),
      client_message_id: "routing_unread_counter_sync"
    )

    assert_equal 1, membership.reload.unread_notifications_count
  end

  private
    def queued_push_user_ids_for(message)
      queued_user_ids = []

      Rails.configuration.x.web_push_pool.stubs(:queue).with do |_payload, subscriptions|
        queued_user_ids.concat(subscriptions.map(&:user_id))
        true
      end
      Room::MessagePusher.new(room: message.room, message: message).push

      queued_user_ids.sort
    end

    def push_payload_for(message)
      Rails.configuration.x.web_push_pool.stubs(:queue)
      Room::MessagePusher.new(room: message.room, message: message).push
    end

    def notification_user_ids(message, activity_type)
      Notification.where(message: message, activity_type: activity_type).pluck(:user_id).sort
    end

    def user_ids(*names)
      names.map { |name| users(name).id }.sort
    end

    def everyone_body
      sgid = Everyone.new.attachable_sgid
      %(<div><action-text-attachment sgid="#{sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment></div>)
    end
end
