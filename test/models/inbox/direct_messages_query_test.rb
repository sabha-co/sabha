require "test_helper"

class Inbox::DirectMessagesQueryTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @kevin = users(:kevin)
  end

  test "returns direct room memberships for user" do
    dm_room = rooms(:david_and_jason)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_includes result.map(&:room), dm_room
  end

  test "excludes non-direct rooms" do
    regular_room = rooms(:watercooler)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:room), regular_room
  end

  test "excludes invisible memberships" do
    dm_room = rooms(:david_and_jason)
    @david.memberships.find_by(room: dm_room).update!(involvement: :invisible)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:room), dm_room
  end

  test "excludes inactive rooms" do
    dm_room = rooms(:david_and_jason)
    dm_room.update!(active: false)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:room), dm_room
  end

  test "orders by room last_active_at descending" do
    dm_room1 = rooms(:david_and_jason)
    dm_room2 = rooms(:david_and_kevin)

    dm_room1.update!(last_active_at: 1.day.ago)
    dm_room2.update!(last_active_at: 1.hour.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_equal dm_room2, result.first.room
    assert_equal dm_room1, result.second.room
  end

  test "includes has_unread_notifications flag" do
    dm_room = rooms(:david_and_jason)
    membership = @david.memberships.find_by(room: dm_room)
    membership.update!(unread_at: 1.hour.ago)

    # Create a message to trigger unread notification
    dm_room.messages.create!(creator: @jason, body: "Hello")

    result = Inbox::DirectMessagesQuery.new(@david).call
    dm_membership = result.find { |m| m.room == dm_room }

    assert dm_membership.respond_to?(:has_unread_notifications?)
  end

  test "last_page returns limited results" do
    result = Inbox::DirectMessagesQuery.new(@david).call.last_page

    assert result.size <= Inbox::DirectMessagesQuery::RoomPagination::PAGE_SIZE
  end

  test "page_after returns memberships with older last_active_at" do
    dm_room1 = rooms(:david_and_jason)
    dm_room2 = rooms(:david_and_kevin)

    dm_room1.update!(last_active_at: 1.hour.ago)
    dm_room2.update!(last_active_at: 2.hours.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call.page_after(dm_room1)

    # Should include dm_room2 which is older
    assert_includes result.map(&:room), dm_room2
    # Should not include dm_room1 which is the anchor
    assert_not_includes result.map(&:room), dm_room1
  end

  test "page_before returns memberships with newer last_active_at" do
    dm_room1 = rooms(:david_and_jason)
    dm_room2 = rooms(:david_and_kevin)

    dm_room1.update!(last_active_at: 1.hour.ago)
    dm_room2.update!(last_active_at: 2.hours.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call.page_before(dm_room2)

    # Should include dm_room1 which is newer
    assert_includes result.map(&:room), dm_room1
    # Should not include dm_room2 which is the anchor
    assert_not_includes result.map(&:room), dm_room2
  end

  test "pagination handles rooms with same last_active_at using id as tie-breaker" do
    dm_room1 = rooms(:david_and_jason)
    dm_room2 = rooms(:david_and_kevin)

    # Set both rooms to the exact same timestamp
    same_time = 1.hour.ago
    dm_room1.update_column(:last_active_at, same_time)
    dm_room2.update_column(:last_active_at, same_time)

    # Determine which room has higher id (appears first in DESC order)
    first_room, second_room = [ dm_room1, dm_room2 ].sort_by(&:id).reverse

    # page_after the first room should include the second room
    result = Inbox::DirectMessagesQuery.new(@david).call.page_after(first_room)
    assert_includes result.map(&:room), second_room

    # page_before the second room should include the first room
    result = Inbox::DirectMessagesQuery.new(@david).call.page_before(second_room)
    assert_includes result.map(&:room), first_room
  end
end
