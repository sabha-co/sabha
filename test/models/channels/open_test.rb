require "test_helper"

class Channels::OpenTest < ActiveSupport::TestCase
  test "does not auto-add users when not auto_join" do
    channel = Channels::Open.create!(name: "Discoverable channel", creator: users(:david))
    assert_equal 0, channel.users.count
  end

  test "grants access to all users when auto_join" do
    channel = Channels::Open.create!(name: "Forced channel", creator: users(:david), auto_join: true)
    assert_equal User.count, channel.users.count
  end

  test "grants access to all users after becoming auto_join open" do
    channel = channels(:watercooler).becomes!(Channels::Open)
    channel.auto_join = true
    channel.save!
    assert_equal User.count, channel.users.count
  end

  test "does not grant access after becoming open without auto_join" do
    channel = channels(:watercooler)
    original_count = channel.users.count
    channel = channel.becomes!(Channels::Open)
    channel.save!
    assert_equal original_count, channel.users.count
  end

  test "new users are auto-joined to existing auto_join channels" do
    channel = Channels::Open.create!(name: "Auto Channel", creator: users(:david), auto_join: true)

    new_user = User.create!(name: "Newcomer", email_address: "newcomer@example.com", password: "secret123456")

    assert channel.memberships.exists?(user: new_user), "New user should be auto-joined to existing auto_join channel"
  end

  test "new users are not auto-joined to channels without auto_join" do
    channel = Channels::Open.create!(name: "Manual Channel", creator: users(:david))

    new_user = User.create!(name: "Newcomer", email_address: "newcomer@example.com", password: "secret123456")

    assert_not channel.memberships.exists?(user: new_user), "New user should not be auto-joined to non-auto_join channel"
  end
end
