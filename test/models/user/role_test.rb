require "test_helper"

class User::RoleTest < ActiveSupport::TestCase
  test "creating subsequent users makes them members" do
    assert User.create!(name: "User", email_address: "user@example.com", password: "secret123456").member?
  end

  test "can_administer?" do
    assert User.new(role: :administrator).can_administer?

    assert_not User.new(role: :member).can_administer?
    assert_not User.new.can_administer?
  end

  test "can administer a record" do
    member = User.new(role: :member)
    assert member.can_administer?(Room.new(creator: member))

    another_member = User.new(role: :member)
    assert another_member.can_administer?(Room.new(creator: member))
    assert_not another_member.can_administer?(rooms(:designers))
  end

  test "bannable_by? rejects self, non-admins, and already-banned users" do
    admin = users(:david)
    other = users(:kevin)

    assert other.bannable_by?(admin)
    assert_not admin.bannable_by?(admin), "admin should not be able to ban themselves"
    assert_not other.bannable_by?(other), "non-admin actor cannot ban anyone"

    other.update_column(:status, User.statuses[:banned])
    assert_not other.bannable_by?(admin), "already-banned user should not be re-bannable"
  end

  test "unbannable_by? rejects self even if banned" do
    admin = users(:david)
    admin.update_column(:status, User.statuses[:banned])

    assert_not admin.unbannable_by?(admin), "admin should not be able to unban themselves"
  end

  test "removable_by? rejects self" do
    admin = users(:david)
    assert_not admin.removable_by?(admin), "admin should not be able to deactivate themselves"
  end
end
