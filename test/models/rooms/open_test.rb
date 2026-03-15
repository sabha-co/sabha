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

  test "new users are auto-joined to existing auto_join rooms" do
    room = Rooms::Open.create!(name: "Auto Room", creator: users(:david), auto_join: true)

    new_user = User.create!(name: "Newcomer", email_address: "newcomer@example.com", password: "secret123456")

    assert room.memberships.exists?(user: new_user), "New user should be auto-joined to existing auto_join room"
  end

  test "new users are not auto-joined to rooms without auto_join" do
    room = Rooms::Open.create!(name: "Manual Room", creator: users(:david))

    new_user = User.create!(name: "Newcomer", email_address: "newcomer@example.com", password: "secret123456")

    assert_not room.memberships.exists?(user: new_user), "New user should not be auto-joined to non-auto_join room"
  end
end
