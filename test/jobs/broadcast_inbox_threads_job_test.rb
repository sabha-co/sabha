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
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: @david)
    thread.memberships.grant_to([ @david, @jason ])

    # First reply triggers the append-to-inbox branch for non-creator participants.
    thread_message = thread.messages.create!(creator: @david, body: "Thread reply")

    assert_turbo_stream_broadcasts [ @jason, :inbox_threads ], count: 1 do
      BroadcastInboxThreadsJob.perform_now(
        thread_id: thread.id,
        parent_message_id: @parent_message.id,
        message_id: thread_message.id,
        creator_id: @david.id
      )
    end
  end

  test "handles missing thread or parent message gracefully" do
    # The job's guard is `return unless thread && parent_message` — exercising
    # both nils in a single test pins the early-return without producing one
    # case per find_by lookup.
    assert_no_turbo_stream_broadcasts [ @jason, :inbox_threads ] do
      BroadcastInboxThreadsJob.perform_now(
        thread_id: -1,
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

    # Creator is the only thread member and no parent room members have :everything
    # involvement, so the broadcast recipient set is empty after removing the creator.
    assert_no_turbo_stream_broadcasts [ @david, :inbox_threads ] do
      assert_no_turbo_stream_broadcasts [ @jason, :inbox_threads ] do
        BroadcastInboxThreadsJob.perform_now(
          thread_id: thread.id,
          parent_message_id: @parent_message.id,
          message_id: thread_message.id,
          creator_id: @david.id
        )
      end
    end
  end
end
