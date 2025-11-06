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
end
