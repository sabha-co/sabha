require "test_helper"

class BroadcastInboxThreadsJobTest < ActiveJob::TestCase
  setup do
    @room = rooms(:designers)
    @david = users(:david)
    @jason = users(:jason)

    # Create a parent message that we'll thread from
    @parent_message = @room.messages.create!(creator: @david, body: "Parent message")
  end

  test "broadcasts to thread participants when thread has messages" do
    # Create a thread room
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    # Create the first message in the thread
    thread_message = thread.messages.create!(creator: @david, body: "Thread reply")

    # Verify job can be performed without errors
    assert_nothing_raised do
      BroadcastInboxThreadsJob.perform_now(
        thread_id: thread.id,
        parent_message_id: @parent_message.id,
        message_id: thread_message.id,
        creator_id: @david.id
      )
    end
  end

  test "handles missing thread gracefully" do
    assert_nothing_raised do
      BroadcastInboxThreadsJob.perform_now(
        thread_id: -1,
        parent_message_id: @parent_message.id,
        message_id: 1,
        creator_id: @david.id
      )
    end
  end

  test "handles missing parent message gracefully" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: @david)

    assert_nothing_raised do
      BroadcastInboxThreadsJob.perform_now(
        thread_id: thread.id,
        parent_message_id: -1,
        message_id: 1,
        creator_id: @david.id
      )
    end
  end

  test "excludes message creator from broadcasts" do
    # Set all parent room members to non-everything involvement so we can test just the thread
    @room.memberships.update_all(involvement: :mentions)

    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: @david)
    thread.memberships.grant_to([ @david ])

    thread_message = thread.messages.create!(creator: @david, body: "Thread reply")

    # When creator is the only thread member and no parent room members have "everything" involvement,
    # no broadcasts should happen (since creator is excluded from the all_user_ids list)
    Turbo::StreamsChannel.expects(:broadcast_append_to).never
    Turbo::StreamsChannel.expects(:broadcast_replace_to).never

    BroadcastInboxThreadsJob.perform_now(
      thread_id: thread.id,
      parent_message_id: @parent_message.id,
      message_id: thread_message.id,
      creator_id: @david.id
    )
  end
end
