require "test_helper"

class SidebarMembershipsTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @kevin = users(:kevin)
    @sidebar = SidebarMemberships.new(@david)
  end

  # --- direct ---

  test "direct returns direct rooms even without messages" do
    # DMs should show as long as they're recently active (within 7 days)
    room = rooms(:david_and_jason)
    room.update!(updated_at: 1.day.ago)

    direct = @sidebar.direct

    assert_includes direct.map(&:room), room
  end

  test "direct returns direct rooms with messages that are recently active" do
    room = rooms(:david_and_jason)
    room.update!(updated_at: 1.day.ago)
    room.messages.create!(creator: @jason, body: "Hello")

    direct = @sidebar.direct

    assert_includes direct.map(&:room), room
  end

  test "direct excludes direct rooms older than 7 days without unread messages" do
    room = rooms(:david_and_jason)
    room.messages.create!(creator: @jason, body: "Hello")

    # Mark as read and set room as old (after message creation to avoid callback updates)
    catch_up @david.memberships.find_by(room: room)
    room.update_columns(updated_at: 10.days.ago)

    direct = @sidebar.direct

    assert_not_includes direct.map(&:room), room
  end

  test "direct includes old direct rooms if they have unread messages" do
    room = rooms(:david_and_jason)
    message = room.messages.create!(creator: @jason, body: "Hello")

    # Mark as unread and set room as old
    rewind_unread_to @david.memberships.find_by(room: room), message
    room.update_columns(updated_at: 10.days.ago)

    direct = @sidebar.direct

    assert_includes direct.map(&:room), room
  end

  test "direct excludes invisible memberships" do
    room = rooms(:david_and_jason)
    room.update!(updated_at: 1.day.ago)
    room.messages.create!(creator: @jason, body: "Hello")

    @david.memberships.find_by(room: room).update!(involvement: :invisible)

    direct = @sidebar.direct

    assert_not_includes direct.map(&:room), room
  end

  test "direct excludes inactive rooms" do
    room = rooms(:david_and_jason)
    room.update!(updated_at: 1.day.ago, active: false)
    room.messages.create!(creator: @jason, body: "Hello")

    direct = @sidebar.direct

    assert_not_includes direct.map(&:room), room
  end

  # --- shared ---

  test "shared returns unstarred open and closed room memberships" do
    shared = @sidebar.shared

    # watercooler and hq are starred in fixtures, so they appear in starred instead
    assert_not_includes shared.map(&:room), rooms(:watercooler)
    assert_not_includes shared.map(&:room), rooms(:hq)
    assert_includes shared.map(&:room), rooms(:pets)
    assert_includes shared.map(&:room), rooms(:designers)
  end

  test "shared excludes direct rooms" do
    shared = @sidebar.shared

    assert_not_includes shared.map(&:room), rooms(:david_and_jason)
    assert_not_includes shared.map(&:room), rooms(:david_and_kevin)
  end

  test "shared excludes invisible memberships" do
    @david.memberships.find_by(room: rooms(:watercooler)).update!(involvement: :invisible)

    shared = @sidebar.shared

    assert_not_includes shared.map(&:room), rooms(:watercooler)
  end

  # --- direct_room_members ---

  test "direct_room_members returns users excluding current user" do
    room = rooms(:david_and_jason)
    room.messages.create!(creator: @jason, body: "Hello")
    membership = @david.memberships.find_by(room: room)

    members = @sidebar.direct_room_members([ membership ])

    assert_equal [ @jason ], members[room.id]
  end

  test "direct_room_members returns current user when they are the only member" do
    # Create a direct room where david is the only member
    room = Rooms::Direct.create!(creator: @david)
    room.memberships.create!(user: @david, involvement: :everything)
    room.messages.create!(creator: @david, body: "Note to self")
    membership = @david.memberships.find_by(room: room)

    members = @sidebar.direct_room_members([ membership ])

    assert_equal [ @david ], members[room.id]
  end

  test "direct_room_members handles multiple rooms" do
    room1 = rooms(:david_and_jason)
    room2 = rooms(:david_and_kevin)
    room1.messages.create!(creator: @jason, body: "Hello")
    room2.messages.create!(creator: @kevin, body: "Hi")

    memberships = [
      @david.memberships.find_by(room: room1),
      @david.memberships.find_by(room: room2)
    ]

    members = @sidebar.direct_room_members(memberships)

    assert_equal [ @jason ], members[room1.id]
    assert_equal [ @kevin ], members[room2.id]
  end
end
