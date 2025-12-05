require "test_helper"

class Users::SidebarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show" do
    get user_sidebar_url

    users(:david).rooms.opens.each do |room|
      assert_match /#{room.name}/, @response.body
    end
  end

  test "unread directs" do
    rooms(:david_and_jason).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Direct rooms only appear once (in direct_rooms section)
    assert_select ".unread", count: users(:david).memberships.select { |m| m.room.direct? && m.unread? }.count
  end


  test "unread other" do
    rooms(:watercooler).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Non-direct rooms appear in both starred_rooms and shared_rooms, so multiply by 2
    unread_count = users(:david).memberships.reject { |m| m.room.direct? || !m.unread? }.count
    assert_select ".unread", count: unread_count * 2
  end

  test "direct room members are preloaded to avoid N+1 queries" do
    # Create messages in direct rooms so they appear in sidebar
    rooms(:david_and_jason).messages.create! client_message_id: 901, body: "Hello", creator: users(:jason)
    rooms(:david_and_kevin).messages.create! client_message_id: 902, body: "Hi", creator: users(:kevin)

    # Count queries during sidebar load
    query_count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      # Count User Load queries that fetch users for direct rooms
      query_count += 1 if payload[:sql] =~ /SELECT.*FROM "users".*"memberships"."room_id"/
    }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get user_sidebar_url
    end

    assert_response :success

    # Should have at most 1 batched query for all direct room users, not N queries
    # (one per room would be N+1)
    assert query_count <= 1, "Expected at most 1 batched user query for direct rooms, got #{query_count}"
  end
end
