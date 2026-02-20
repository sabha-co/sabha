require "test_helper"

class Rooms::OpenTest < ActiveSupport::TestCase
  test "does not auto-add users when not auto_join" do
    room = Rooms::Open.create!(name: "Discoverable room", creator: users(:david))
    assert_equal 0, room.users.count
  end

  test "grants access to all users when auto_join" do
    room = Rooms::Open.create!(name: "Forced room", creator: users(:david), auto_join: true)
    assert_equal User.count, room.users.count
  end

  test "grants access to all users after becoming auto_join open" do
    room = rooms(:watercooler).becomes!(Rooms::Open)
    room.auto_join = true
    room.save!
    assert_equal User.count, room.users.count
  end

  test "does not grant access after becoming open without auto_join" do
    room = rooms(:watercooler)
    original_count = room.users.count
    room = room.becomes!(Rooms::Open)
    room.save!
    assert_equal original_count, room.users.count
  end
end
