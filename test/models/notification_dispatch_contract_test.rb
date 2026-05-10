require "test_helper"

# Locks contracts the planned unified-dispatch refactor will rely on but that
# `notification_routing_parity_test.rb` does not assert directly. Each test
# pins a piece of current behavior the dispatcher cannot regress without
# silently breaking notification routing.
#
# When the refactor lands, these stay green if the contracts are preserved.
# If a test fails, the dispatcher has shifted a load-bearing assumption —
# confirm the change is intentional before updating the assertion.
class NotificationDispatchContractTest < ActiveSupport::TestCase
  # The new `Notification::DispatchJob` callback will be appended to this
  # chain and must read mention rows + thread-reply enqueue state set by
  # earlier callbacks. If a future change reorders or removes any of these,
  # the dispatcher needs to be re-pointed before merging.
  test "Message after_create_commit callbacks fire in the order the dispatcher depends on" do
    expected_order = %i[
      deliver_to_room
      involve_creator_in_thread
      update_thread_reply_count
      update_parent_message_threads
      update_creator_streak
      create_mention_notifications
      create_thread_reply_notifications
      increment_unread_notifications_counters
      dispatch_notifications
    ]

    # `_commit_callbacks.to_a` returns storage order (reverse of execution).
    # Reverse so the assertion reads top-to-bottom in execution order, matching
    # the declaration sequence in app/models/message.rb.
    symbol_filters = Message._commit_callbacks.to_a.map(&:filter).grep(Symbol).reverse
    observed_order = symbol_filters.select { |sym| expected_order.include?(sym) }

    assert_equal expected_order, observed_order,
      "Message after_create_commit callback order changed. The unified dispatcher " \
      "callback assumes create_mention_notifications and create_thread_reply_notifications " \
      "have already run when it fires. Re-validate dispatcher placement before merging."
  end

  test "create_mention_notifications writes rows synchronously so a later callback can read them" do
    message = rooms(:designers).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: users(:david),
      client_message_id: "dispatch_contract_mention_sync"
    )

    assert_equal [ users(:kevin).id ],
      Notification.where(message_id: message.id, activity_type: "mention").pluck(:user_id)
  end

  test "create_thread_reply_notifications enqueues its job synchronously so a later callback can observe it" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent for dispatch contract",
      creator: users(:david),
      client_message_id: "dispatch_contract_thread_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])

    assert_enqueued_with(job: CreateThreadReplyNotificationsJob) do
      thread.messages.create!(
        body: "Thread reply for dispatch contract",
        creator: users(:jason),
        client_message_id: "dispatch_contract_thread_reply"
      )
    end
  end

  # The push pipeline assumes `involved_in_everything` and `involved_in_mentions`
  # are disjoint subsets of memberships — `Room::MessagePusher` runs them as
  # parallel scopes and dedups by user_id only at the @everyone overlap, not at
  # the involvement-scope level. If the enum gains a fifth state or the values
  # collide, push routing splits silently.
  test "Membership.involved_in_everything and .involved_in_mentions are disjoint" do
    everything_ids = Membership.involved_in_everything.pluck(:id)
    mentions_ids   = Membership.involved_in_mentions.pluck(:id)

    assert_empty everything_ids & mentions_ids
    assert_equal [ "everything" ], Membership.involved_in_everything.distinct.pluck(:involvement)
    assert_equal [ "mentions" ],   Membership.involved_in_mentions.distinct.pluck(:involvement)
  end

  # The `Notification::Routing` vocabulary
  # (`%i[mention direct_message everyone_room_message thread_reply boost]`)
  # is broader than the persisted `Notification.activity_type` enum and must
  # stay that way — the dispatcher routes those symbols, but only three of
  # them ever land in the table.
  test "Notification.activity_type accepts only the three persisted vocabulary values" do
    message = rooms(:pets).messages.create!(
      body: "Activity type boundary",
      creator: users(:david),
      client_message_id: "dispatch_contract_activity_type"
    )

    %w[mention boost thread_reply].each do |valid|
      notification = Notification.new(
        user: users(:jason), message: message, actor: users(:david), activity_type: valid
      )
      assert notification.valid?, "Expected '#{valid}' to be a valid activity_type"
    end

    %w[direct_message everyone_room_message].each do |routing_only|
      notification = Notification.new(
        user: users(:jason), message: message, actor: users(:david), activity_type: routing_only
      )
      refute notification.valid?,
        "'#{routing_only}' is dispatcher-only routing vocabulary and must not be persistable as activity_type"
    end
  end

  # A single message in a thread can be both a thread_reply (for non-mentioned
  # thread members) and a named mention (for the recipient). Today these are
  # produced by two separate callbacks; the dispatcher refactor must still
  # produce both rows for the same message without one path masking the other.
  test "a thread reply that mentions someone produces both mention and thread_reply rows" do
    parent = rooms(:pets).messages.create!(
      body: "Thread parent for combo",
      creator: users(:jason),
      client_message_id: "dispatch_contract_combo_parent"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:jason))
    thread.memberships.grant_to([ users(:david), users(:jz) ])
    thread.memberships.find_by(user: users(:jz)).update!(involvement: "mentions")

    reply = thread.messages.create!(
      body: "<div>Replying with #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "dispatch_contract_combo_reply"
    )
    perform_enqueued_jobs(only: CreateThreadReplyNotificationsJob)

    rows_by_type = Notification.where(message_id: reply.id)
                               .pluck(:activity_type, :user_id)
                               .group_by(&:first)
                               .transform_values { |pairs| pairs.map(&:last).sort }

    assert_equal [ users(:david).id ], rows_by_type["mention"],
      "thread reply that @mentions a user must still create the mention row"
    assert_equal [ users(:jz).id ], rows_by_type["thread_reply"],
      "thread reply must still create thread_reply rows for non-mentioned thread members"
  end
end
