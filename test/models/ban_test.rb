require "test_helper"

class BanTest < ActiveSupport::TestCase
  test "validates ip_address presence" do
    ban = Ban.new(user: users(:david))
    assert_not ban.valid?
    assert_includes ban.errors[:ip_address], "can't be blank"
  end

  test "validates ip_address is public" do
    ban = Ban.new(user: users(:david), ip_address: "127.0.0.1")
    assert_not ban.valid?
    assert_includes ban.errors[:ip_address], "cannot be a private or internal IP address"

    ban = Ban.new(user: users(:david), ip_address: "192.168.1.1")
    assert_not ban.valid?
    assert_includes ban.errors[:ip_address], "cannot be a private or internal IP address"

    ban = Ban.new(user: users(:david), ip_address: "169.254.169.254")
    assert_not ban.valid?
    assert_includes ban.errors[:ip_address], "cannot be a private or internal IP address"
  end

  test "validates ip_address format" do
    ban = Ban.new(user: users(:david), ip_address: "invalid")
    assert_not ban.valid?
    assert_includes ban.errors[:ip_address], "is not a valid IP address"
  end

  test "accepts valid public ip address" do
    ban = Ban.new(user: users(:david), ip_address: "203.0.113.1")
    assert ban.valid?
  end

  test "banned? returns true for banned ip" do
    Ban.create!(user: users(:david), ip_address: "203.0.113.1")
    assert Ban.banned?("203.0.113.1")
  end

  test "banned? returns false for non-banned ip" do
    assert_not Ban.banned?("203.0.113.99")
  end
end
