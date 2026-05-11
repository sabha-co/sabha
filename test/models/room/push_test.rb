require "test_helper"

class Room::PushTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "deliver new message to other room users with push subscriptions" do
    task_count = Push::Subscription.count - users(:david).push_subscriptions.count
    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(task_count)
      rooms(:hq).messages.create! body: "This is from earth", client_message_id: "earth", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(task_count)
  end

  test "notifies subscribed users" do
    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(2)
      rooms(:designers).messages.create! body: "This is from earth", client_message_id: "earth", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(2)

    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(3)
      rooms(:designers).messages.create! body: "Hey #{mention_attachment_for(:kevin)}", client_message_id: "earth", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(5)
  end

  test "does not notify for connected rooms" do
    memberships(:kevin_designers).connected

    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(2)
      rooms(:designers).messages.create! body: "Hey @kevin", client_message_id: "earth", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(2)
  end

  test "does not notify for invisible rooms" do
    memberships(:kevin_designers).update! involvement: "invisible"

    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(2)
      rooms(:designers).messages.create! body: "Hey @kevin", client_message_id: "earth", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(2)
  end

  test "does not push to a recipient who has blocked the sender" do
    # Baseline: david @-mentions kevin in designers — jason (everything),
    # jz (everything), and kevin (mentions, named) all push → 3. With kevin
    # blocking david, kevin's mention push is suppressed → 2.
    users(:kevin).block!(users(:david))

    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(2)
      rooms(:designers).messages.create! body: "Hey #{mention_attachment_for(:kevin)}", client_message_id: "blocked_push_#{SecureRandom.hex(4)}", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(2)
  end

  test "does not push when the recipient's push_enabled setting is off" do
    (users(:kevin).notification_settings || users(:kevin).create_notification_settings!).update!(push_enabled: false)

    # Same baseline as above: 3 pushes for a kevin-mention from david. With
    # kevin's push_enabled flipped off → 2.
    perform_enqueued_jobs only: Notification::DispatchJob do
      WebPush.expects(:payload_send).times(2)
      rooms(:designers).messages.create! body: "Hi #{mention_attachment_for(:kevin)}", client_message_id: "push_off_#{SecureRandom.hex(4)}", creator: users(:david)
    end
    wait_for_web_push_delivery_pool_tasks(2)
  end

  test "block check stays O(1) in candidate count — at most two block queries per dispatch" do
    # Without memoization, each candidate triggers two `Block.exists?` calls via
    # User#can_ping?. For an @everyone push in a large room that would be 2×N
    # queries. The cache on Message#blocked_user_ids_with_creator caps it at 2.
    sender    = users(:david)
    room      = rooms(:designers)
    activity  = :everyone_room_message

    message = room.messages.new(body: "<div>perf</div>", creator: sender, client_message_id: "perf_#{SecureRandom.hex(4)}")
    # Materialize without firing dispatch callbacks — we only care about the
    # predicate hot path, not delivery.
    message.save!(validate: false)

    block_query_count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      block_query_count += 1 if payload[:sql].to_s.match?(/FROM\s+"blocks"/i)
    }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      message.push_recipient_user_ids_for(activity)
    end

    assert_operator block_query_count, :<=, 2,
      "expected at most 2 block queries per dispatch regardless of candidate count, got #{block_query_count}"
  end

  test "destroys invalid subscriptions" do
    memberships(:kevin_designers).update! involvement: "invisible"

    assert_difference -> { Push::Subscription.count }, -2 do
      perform_enqueued_jobs only: Notification::DispatchJob do
        WebPush.expects(:payload_send).times(2).raises(WebPush::ExpiredSubscription.new(Struct.new(:body).new, "example.com"))
        rooms(:designers).messages.create! body: "Hey @kevin", client_message_id: "earth", creator: users(:david)
      end
      wait_for_web_push_delivery_pool_tasks(2)
      wait_for_invalidation_pool_tasks(2)
    end
  end

  private
    def wait_for_web_push_delivery_pool_tasks(count)
      wait_for_pool_tasks(Rails.configuration.x.web_push_pool.delivery_pool, count)
    end

    def wait_for_invalidation_pool_tasks(count)
      wait_for_pool_tasks(Rails.configuration.x.web_push_pool.invalidation_pool, count)
    end

    def wait_for_pool_tasks(pool, count)
      start = Time.now
      timeout = 2.0  # Increased timeout for slower CI/test environments
      while pool.completed_task_count < count
        raise "Timeout waiting for pool tasks to complete" if Time.now - start > timeout
        sleep 0.01
      end
    end
end
