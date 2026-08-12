require "test_helper"

class Room::RosterTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:designers)
    # Start from a clean slate: nobody connected until a test says so.
    @room.memberships.active.update_all(connections: 0, connected_at: nil)
  end

  test "a fresh, connected member is here now" do
    place memberships(:jz_designers), connections: 1, connected_at: 1.minute.ago

    assert_includes here_now_names, users(:jz).name
    assert_not_includes away_names, users(:jz).name
  end

  test "a member seen within the hour but not connected is away" do
    place memberships(:jz_designers), connections: 0, connected_at: 20.minutes.ago

    assert_includes away_names, users(:jz).name
    assert_not_includes here_now_names, users(:jz).name
  end

  test "a member with a stale socket refcount reads as away, not here now" do
    # Refcount never dropped (a socket died without departing) but last-seen has
    # gone cold — the freshness half of `connected` catches it.
    place memberships(:jz_designers), connections: 1, connected_at: 30.minutes.ago

    assert_includes away_names, users(:jz).name
    assert_not_includes here_now_names, users(:jz).name
  end

  test "a member last seen over an hour ago counts as offline" do
    place memberships(:jz_designers), connections: 0, connected_at: 2.hours.ago

    assert_not_includes here_now_names, users(:jz).name
    assert_not_includes away_names, users(:jz).name
  end

  test "offline_count is everyone not here now or away" do
    place memberships(:jz_designers),    connections: 1, connected_at: 1.minute.ago
    place memberships(:jason_designers), connections: 0, connected_at: 20.minutes.ago

    roster = Room::Roster.new(@room)
    total = @room.visible_users.active.count
    assert_equal total - 2, roster.offline_count
  end

  private
    def place(membership, attributes)
      membership.update!(attributes)
    end

    def here_now_names
      Room::Roster.new(@room).here_now.map(&:name)
    end

    def away_names
      Room::Roster.new(@room).away.map(&:name)
    end
end
