require "test_helper"

class Rooms::RefreshesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "refresh includes new messages since the last known" do
    travel_to 1.day.ago do
      @old_message = rooms(:hq).messages.create!(creator: users(:jason), body: "Old message", client_message_id: "old")
    end

    travel_to 1.minute.ago do
      @new_message = rooms(:hq).messages.create!(creator: users(:jason), body: "New message", client_message_id: "new")
      @old_message.touch
    end

    get room_refresh_url(rooms(:hq), format: :turbo_stream), params: { since: 10.minutes.ago.to_fs(:epoch) }

    assert_response :success

    assert_select "turbo-stream[action='append']" do
      assert_select "#" + dom_id(@new_message)
      assert_select "template", count: 1
    end

    assert_select "turbo-stream[action='replace']" do
      assert_select "#" + dom_id(@old_message)
      assert_select "template", count: 1
    end
  end

  test "refresh loads thread associations in at most two queries as threaded message count grows" do
    room = rooms(:hq)
    setup_refresh_messages(room, prefix: "five", count: 5)

    thread_preload_queries = count_thread_association_queries do
      get room_refresh_url(room, format: :turbo_stream), params: { since: 10.minutes.ago.to_fs(:epoch) }
      assert_response :success
    end

    assert_operator thread_preload_queries, :<=, 2
  end

  private
    def setup_refresh_messages(room, prefix:, count:)
      count.times do |i|
        old_parent = nil

        travel_to 1.day.ago do
          old_parent = room.messages.create!(
            creator: users(:jason),
            body: "#{prefix} old parent #{i}",
            client_message_id: "#{prefix}_old_parent_#{i}"
          )

          old_thread = Rooms::Thread.create!(parent_message: old_parent, creator: users(:jason))
          old_thread.memberships.grant_to(users(:jason))
          old_thread.messages.create!(
            creator: users(:jason),
            body: "#{prefix} old reply #{i}",
            client_message_id: "#{prefix}_old_reply_#{i}"
          )
        end

        travel_to 1.minute.ago do
          room.messages.create!(
            creator: users(:jason),
            body: "#{prefix} new parent #{i}",
            client_message_id: "#{prefix}_new_parent_#{i}"
          ).tap do |new_parent|
            new_thread = Rooms::Thread.create!(parent_message: new_parent, creator: users(:jason))
            new_thread.memberships.grant_to(users(:jason))
            new_thread.messages.create!(
              creator: users(:jason),
              body: "#{prefix} new reply #{i}",
              client_message_id: "#{prefix}_new_reply_#{i}"
            )
          end

          old_parent.touch
        end
      end
    end

    def count_thread_association_queries
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql]
        name = payload[:name]
        next if payload[:cached]
        next if name == "SCHEMA"
        next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
        next unless sql.match?(/FROM "rooms".*"parent_message_id"/)

        @query_count += 1
      end

      @query_count = 0
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      end
      @query_count
    end
end
