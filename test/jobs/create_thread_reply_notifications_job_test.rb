require "test_helper"

class CreateThreadReplyNotificationsJobTest < ActiveJob::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @jz = users(:jz)
    @room = rooms(:pets)
  end

  test "creates notifications for visible thread members" do
    parent = @room.messages.create!(body: "Thread parent", creator: @jason, client_message_id: "job_parent_1")
    thread = Rooms::Thread.create!(parent_message: parent, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :mentions)

    reply = thread.messages.create!(body: "Reply", creator: @jason, client_message_id: "job_reply_1")

    assert_turbo_stream_broadcasts [ @david, :inbox_activity ], count: 1 do
      assert_turbo_stream_broadcasts [ @david, :sidebar_activity_indicator ], count: 1 do
        CreateThreadReplyNotificationsJob.perform_now(
          message_id: reply.id,
          thread_id: thread.id,
          creator_id: @jason.id
        )
      end
    end

    assert Notification.exists?(user: @david, message: reply, activity_type: "thread_reply")
  end

  test "excludes the message creator" do
    parent = @room.messages.create!(body: "Thread parent", creator: @david, client_message_id: "job_parent_2")
    thread = Rooms::Thread.create!(parent_message: parent, creator: @david)
    thread.memberships.grant_to(@jason)
    thread.memberships.find_by(user: @jason).update!(involvement: :mentions)

    reply = thread.messages.create!(body: "Reply", creator: @jason, client_message_id: "job_reply_2")

    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: @jason.id
    )

    assert_not Notification.exists?(user: @jason, message: reply, activity_type: "thread_reply")
  end

  test "skips users who already have a mention notification" do
    parent = @room.messages.create!(body: "Thread parent", creator: @jason, client_message_id: "job_parent_3")
    thread = Rooms::Thread.create!(parent_message: parent, creator: @jason)
    thread.memberships.grant_to(@david)
    thread.memberships.find_by(user: @david).update!(involvement: :mentions)

    # Create a reply that also @mentions david
    reply = thread.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "job_reply_3"
    )

    # Mention notification already created by Message callback
    assert Notification.exists?(user: @david, message: reply, activity_type: "mention")

    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: @jason.id
    )

    # Should NOT create a duplicate thread_reply notification
    assert_not Notification.exists?(user: @david, message: reply, activity_type: "thread_reply")
  end

  test "handles missing thread gracefully" do
    assert_nothing_raised do
      CreateThreadReplyNotificationsJob.perform_now(
        message_id: 999999,
        thread_id: 999999,
        creator_id: @jason.id
      )
    end
  end

  test "creates notifications for everything-involved parent room members" do
    parent = @room.messages.create!(body: "Thread parent", creator: @jason, client_message_id: "job_parent_4")

    # Give david "everything" involvement in the parent room
    @room.memberships.find_by(user: @david).update!(involvement: :everything)

    thread = Rooms::Thread.create!(parent_message: parent, creator: @jason)
    # David has no direct thread membership, but has "everything" in parent room

    reply = thread.messages.create!(body: "Reply", creator: @jason, client_message_id: "job_reply_4")

    CreateThreadReplyNotificationsJob.perform_now(
      message_id: reply.id,
      thread_id: thread.id,
      creator_id: @jason.id
    )

    assert Notification.exists?(user: @david, message: reply, activity_type: "thread_reply")
  end
end
