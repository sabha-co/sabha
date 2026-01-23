require "test_helper"

class Rooms::DirectGroupTest < ActiveSupport::TestCase
  test "create group DM with three users" do
    # Use existing fixture room creation pattern - the first user becomes creator
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    assert room.direct?
    assert_equal 3, room.users.count
    assert room.users.include?(users(:david))
    assert room.users.include?(users(:jason))
    assert room.users.include?(users(:jz))
  end

  test "group DM order does not matter for finding existing room" do
    room1 = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    # find_or_create_for should find the same room regardless of order
    room2 = Rooms::Direct.find_or_create_for([ users(:jz), users(:david), users(:jason) ])

    assert_equal room1, room2
  end

  test "group DM with different users creates different room" do
    room1 = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])
    room2 = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:kevin) ])

    assert_not_equal room1, room2
  end

  test "group DM default involvement is everything for all users" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    room.memberships.each do |membership|
      assert membership.involved_in_everything?, "Expected #{membership.user.name} to have everything involvement"
    end
  end

  test "group DM display name shows all other users" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    display_name = room.display_name(for_user: users(:david))
    assert_includes display_name, "Jason"
    assert_includes display_name, "JZ"
    assert_not_includes display_name, "David"
  end

  test "single user DM (note to self)" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david) ])

    assert room.direct?
    assert_equal 1, room.users.count
    assert room.users.include?(users(:david))
  end

  test "single user DM display name shows own name" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david) ])

    display_name = room.display_name(for_user: users(:david))
    assert_equal "David", display_name
  end

  test "group DM with four users" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz), users(:kevin) ])

    assert room.direct?
    assert_equal 4, room.users.count
  end

  test "idempotent room creation via find_or_create_for" do
    # Create room via create_for first (use users without existing fixture DMs)
    room1 = Rooms::Direct.create_for({ creator: users(:jz) }, users: [ users(:jz), users(:rachel) ])

    # find_or_create_for should find existing room
    room2 = Rooms::Direct.find_or_create_for([ users(:jz), users(:rachel) ])

    assert_equal room1, room2
  end
end
