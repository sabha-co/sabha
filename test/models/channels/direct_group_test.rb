require "test_helper"

class Channels::DirectGroupTest < ActiveSupport::TestCase
  test "create group DM with three users" do
    # Use existing fixture channel creation pattern - the first user becomes creator
    channel = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    assert channel.direct?
    assert_equal 3, channel.users.count
    assert channel.users.include?(users(:david))
    assert channel.users.include?(users(:jason))
    assert channel.users.include?(users(:jz))
  end

  test "group DM order does not matter for finding existing channel" do
    channel1 = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    # find_or_create_for should find the same channel regardless of order
    channel2 = Channels::Direct.find_or_create_for([ users(:jz), users(:david), users(:jason) ])

    assert_equal channel1, channel2
  end

  test "group DM default involvement is everything for all users" do
    channel = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    channel.memberships.each do |membership|
      assert membership.involved_in_everything?, "Expected #{membership.user.name} to have everything involvement"
    end
  end

  test "group DM display name shows all other users" do
    channel = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:jason), users(:jz) ])

    display_name = channel.display_name(for_user: users(:david))
    assert_includes display_name, "Jason"
    assert_includes display_name, "JZ"
    assert_not_includes display_name, "David"
  end

  test "single user DM (note to self)" do
    channel = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david) ])

    assert channel.direct?
    assert_equal 1, channel.users.count
    assert channel.users.include?(users(:david))
  end

  test "single user DM display name shows own name" do
    channel = Channels::Direct.create_for({ creator: users(:david) }, users: [ users(:david) ])

    display_name = channel.display_name(for_user: users(:david))
    assert_equal "David", display_name
  end

  test "idempotent channel creation via find_or_create_for" do
    # Create channel via create_for first (use users without existing fixture DMs)
    channel1 = Channels::Direct.create_for({ creator: users(:jz) }, users: [ users(:jz), users(:rachel) ])

    # find_or_create_for should find existing channel
    channel2 = Channels::Direct.find_or_create_for([ users(:jz), users(:rachel) ])

    assert_equal channel1, channel2
  end
end
