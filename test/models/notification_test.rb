require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = rooms(:pets)
  end

  test "creating a message with @mention creates a mention notification" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "mention_notif_test"
    )

    notification = Notification.find_by(user: @david, message: message, activity_type: "mention")
    assert notification, "Mention notification should be created"
    assert_equal @jason.id, notification.actor_id
    assert_nil notification.boost_id
  end

  test "self-mention does not create a notification" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @david,
      client_message_id: "self_mention_notif"
    )

    assert_not Notification.exists?(user: @david, message: message)
  end

  test "DM messages do not create mention notifications" do
    dm_room = rooms(:david_and_jason)
    message = dm_room.messages.create!(
      body: "Hey David",
      creator: @jason,
      client_message_id: "dm_notif_test"
    )

    assert_not Notification.exists?(message: message, activity_type: "mention")
  end

  test "DM boosts do not create notifications" do
    dm_room = rooms(:david_and_jason)
    message = dm_room.messages.create!(
      body: "Boost me",
      creator: @david,
      client_message_id: "dm_boost_notif"
    )

    message.boosts.create!(content: "🔥", booster: @jason)

    assert_not Notification.exists?(message: message, activity_type: "boost")
  end

  test "mentions in DM threads do not create notifications" do
    dm_room = rooms(:david_and_jason)
    parent = dm_room.messages.create!(body: "Start thread", creator: @david, client_message_id: "dm_thread_parent")
    thread = Rooms::Thread.find_or_create_by!(parent_message: parent, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    thread.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "dm_thread_mention"
    )

    assert_not Notification.exists?(activity_type: "mention", message: thread.messages.last)
  end

  test "boosts in DM threads do not create notifications" do
    dm_room = rooms(:david_and_jason)
    parent = dm_room.messages.create!(body: "Start thread", creator: @david, client_message_id: "dm_thread_boost_parent")
    thread = Rooms::Thread.find_or_create_by!(parent_message: parent, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    thread_msg = thread.messages.create!(body: "Boost me", creator: @david, client_message_id: "dm_thread_boost_msg")
    thread_msg.boosts.create!(content: "🔥", booster: @jason)

    assert_not Notification.exists?(activity_type: "boost", message: thread_msg)
  end

  test "creating a boost creates a notification for message creator" do
    message = @room.messages.create!(
      body: "Boost me",
      creator: @david,
      client_message_id: "boost_notif_test"
    )

    boost = nil
    perform_enqueued_jobs(only: Notification::DispatchJob) do
      boost = message.boosts.create!(content: "🔥", booster: @jason)
    end

    notification = Notification.find_by(user: @david, activity_type: "boost", boost_id: boost.id)
    assert notification, "Boost notification should be created"
    assert_equal @jason.id, notification.actor_id
    assert_equal message.id, notification.message_id
  end

  test "boosting your own message does not create a notification" do
    message = @room.messages.create!(
      body: "Self boost",
      creator: @david,
      client_message_id: "self_boost_test"
    )

    boost = message.boosts.create!(content: "🔥", booster: @david)

    assert_not Notification.exists?(boost_id: boost.id)
  end

  test "destroying a boost destroys its notification" do
    message = @room.messages.create!(
      body: "Boost then delete",
      creator: @david,
      client_message_id: "boost_deactivate_test"
    )

    boost = nil
    perform_enqueued_jobs(only: Notification::DispatchJob) do
      boost = message.boosts.create!(content: "🔥", booster: @jason)
    end
    assert Notification.exists?(boost_id: boost.id)

    boost.destroy!
    assert_not Notification.exists?(boost_id: boost.id)
  end

  test "soft-deleting a message destroys its notifications" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "msg_deactivate_test"
    )

    assert Notification.exists?(message: message)

    message.deactivate!
    assert_not Notification.exists?(message: message)
  end

  test "activity_type validation" do
    message = @room.messages.create!(body: "test", creator: @jason, client_message_id: "valid_test")

    notification = Notification.new(
      user: @david, message: message, actor: @jason, activity_type: "invalid"
    )
    assert_not notification.valid?

    notification.activity_type = "mention"
    assert notification.valid?
  end

  test "@everyone mention creates notifications for all room members except creator" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div>Hey <action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    room_user_ids = @room.user_ids
    assert room_user_ids.size > 1, "Room should have multiple members for this test"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_notif_test"
    )

    notifications = Notification.where(message: message, activity_type: "mention")
    expected_ids = (room_user_ids - [ @jason.id ]).sort
    assert_equal expected_ids, notifications.pluck(:user_id).sort
    assert_not_includes notifications.pluck(:user_id), @jason.id
  end

  test "editing a mention out of a message destroys the notification" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "edit_mention_out"
    )

    assert Notification.exists?(user: @david, message: message, activity_type: "mention")

    # Edit the message to remove the mention
    message.update!(body: "<div>Hey everyone</div>")

    assert_not Notification.exists?(user: @david, message: message, activity_type: "mention")
  end

  test "editing @everyone to individual mention destroys non-mentioned users notifications" do
    # Add a third member so @everyone notifies more than one person
    jz = users(:jz)
    @room.memberships.create!(user: jz, involvement: :everything)

    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_to_individual"
    )

    # Everyone in room (except jason) should have a notification
    room_recipients = @room.user_ids - [ @jason.id ]
    assert room_recipients.size > 1
    assert_equal room_recipients.sort, Notification.where(message: message, activity_type: "mention").pluck(:user_id).sort

    # Edit to only mention david
    message.update!(body: "<div>Hey #{mention_attachment_for(:david)}</div>")

    # David should still have notification, others should not
    remaining = Notification.where(message: message, activity_type: "mention")
    assert_includes remaining.pluck(:user_id), @david.id
    assert_equal 1, remaining.count
  end

  test "room deactivation destroys all notifications for messages in that room" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "room_deactivate_notif"
    )

    assert Notification.exists?(user: @david, message: message)

    @room.deactivate

    assert_not Notification.exists?(user: @david, message: message)
  end

  test "non-body update does not destroy mention notifications" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "non_body_update"
    )

    assert Notification.exists?(user: @david, message: message, activity_type: "mention")

    # Update a non-body attribute — should NOT trigger stale mention check
    message.update!(mentions_everyone: false)

    assert Notification.exists?(user: @david, message: message, activity_type: "mention"),
      "Mention notification should survive non-body updates"
  end

  test "editing out a mention then editing it back does not restore the notification" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "re_mention_test"
    )

    assert Notification.exists?(user: @david, message: message, activity_type: "mention")

    # Edit out the mention
    message.update!(body: "<div>No mention</div>")
    assert_not Notification.exists?(user: @david, message: message, activity_type: "mention")

    # Re-add the mention — notifications are only created on message create, not update
    message.update!(body: "<div>Hey #{mention_attachment_for(:david)}</div>")
    assert_not Notification.exists?(user: @david, message: message, activity_type: "mention"),
      "Re-mentioning via edit does not re-create notifications (create-only)"
  end

  test "quoting a message creates mention notification for original author" do
    original_message = @room.messages.create!(
      body: "<div>Original message</div>",
      creator: @david,
      client_message_id: "cited_notif_original"
    )

    citing_message = @room.messages.create!(
      body: "<div><cite><a href=\"/rooms/#{@room.id}/messages/@#{original_message.id}\">quoted</a></cite> responding</div>",
      creator: @jason,
      client_message_id: "cited_notif_reply"
    )

    assert Notification.exists?(user: @david, message: citing_message, activity_type: "mention"),
      "Quoted author should get a mention notification"
  end

  test "mentioning a non-member creates no notification" do
    jz = users(:jz)
    assert_not @room.memberships.exists?(user: jz), "jz should not be a member of the room"

    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jz)}</div>",
      creator: @jason,
      client_message_id: "non_member_notif"
    )

    assert_not Notification.exists?(user: jz, message: message),
      "Non-member should not receive a notification"
    assert_not @room.memberships.exists?(user: jz),
      "Non-member should not be added to the room"
  end

  test "creating a mention notification broadcasts the activity indicator" do
    assert_turbo_stream_broadcasts [ @david, :sidebar_activity_indicator ], count: 1 do
      perform_enqueued_jobs(only: BroadcastMentionNotificationsJob) do
        @room.messages.create!(
          body: "<div>Hey #{mention_attachment_for(:david)}</div>",
          creator: @jason,
          client_message_id: "indicator_broadcast_mention"
        )
      end
    end
  end

  test "creating a boost notification broadcasts the activity indicator" do
    message = @room.messages.create!(body: "boost me", creator: @david, client_message_id: "indicator_broadcast_boost")

    assert_turbo_stream_broadcasts [ @david, :sidebar_activity_indicator ], count: 1 do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        message.boosts.create!(content: "🔥", booster: @jason)
      end
    end
  end

  test "creating a thread reply notification broadcasts the activity indicator" do
    parent = @room.messages.create!(body: "start", creator: @david, client_message_id: "indicator_broadcast_parent")
    thread = Rooms::Thread.find_or_create_by!(parent_message: parent, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    assert_turbo_stream_broadcasts [ @david, :sidebar_activity_indicator ], count: 1 do
      perform_enqueued_jobs(only: CreateThreadReplyNotificationsJob) do
        thread.messages.create!(body: "reply", creator: @jason, client_message_id: "indicator_broadcast_reply")
      end
    end
  end

  test "delete_all_and_broadcast fires the activity indicator broadcast for affected users" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "indicator_broadcast_bulk_delete"
    )

    assert_turbo_stream_broadcasts [ @david, :sidebar_activity_indicator ], count: 1 do
      Notification.delete_all_and_broadcast(Notification.where(message_id: message.id))
    end
  end
end
