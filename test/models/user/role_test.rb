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
end
