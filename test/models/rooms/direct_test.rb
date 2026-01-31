require "test_helper"

class Rooms::DirectTest < ActiveSupport::TestCase
  test "create room for same users" do
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    assert room.users.include?(users(:david))
    assert room.users.include?(users(:kevin))
    assert_not room.users.include?(users(:jason))
  end

  test "only one room will exist for the same users" do
    room1 = Rooms::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    room2 = Rooms::Direct.find_or_create_for([ users(:kevin), users(:david) ])
    assert_equal room1, room2
  end

  test "default involvement for new users" do
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    assert room.memberships.all? { |m| m.involved_in_everything? }
  end

  test "broadcasts to sidebar for each member on creation" do
    jz = users(:jz)
    rachel = users(:rachel)
    Current.user = jz

    jz_stream = "#{jz.to_gid_param}:rooms"
    rachel_stream = "#{rachel.to_gid_param}:rooms"

    assert_broadcasts jz_stream, 1 do
      assert_broadcasts rachel_stream, 1 do
        Rooms::Direct.find_or_create_for([ jz, rachel ])
      end
    end
  end

  test "one_on_one? returns true for two-person DM" do
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ])
    assert room.one_on_one?
  end

  test "one_on_one? returns false for group DM" do
    Current.user = users(:david)
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason), users(:kevin) ])
    assert_not room.one_on_one?
  end

  test "other_user returns the other participant in one-on-one DM" do
    Current.user = users(:david)
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ])

    assert_equal users(:jason), room.other_user
  end

  test "other_user returns nil for group DM" do
    Current.user = users(:david)
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason), users(:kevin) ])

    assert_nil room.other_user
  end

  test "other_user accepts for_user parameter" do
    room = Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ])

    assert_equal users(:jason), room.other_user(for_user: users(:david))
    assert_equal users(:david), room.other_user(for_user: users(:jason))
  end
end
