require "test_helper"

class BadgeTest < ActiveSupport::TestCase
  test "valid badge" do
    badge = Badge.new(name: "Test")
    assert badge.valid?
  end

  test "requires name" do
    badge = Badge.new(name: "")
    assert_not badge.valid?
    assert_includes badge.errors[:name], "can't be blank"
  end

  test "name cannot exceed 10 characters" do
    badge = Badge.new(name: "a" * 11)
    assert_not badge.valid?
    assert badge.errors[:name].any? { |e| e.include?("too long") }
  end

  test "color must be valid hex format" do
    badge = Badge.new(name: "Test", color: "red")
    assert_not badge.valid?
    assert badge.errors[:color].any?

    badge.color = "#ff0000"
    assert badge.valid?
  end

  test "color allows blank" do
    badge = Badge.new(name: "Test", color: "")
    assert badge.valid?
  end

  test "ordered scope sorts by name" do
    badges(:vip).update!(name: "Alpha")
    badges(:founder).update!(name: "Beta")
    badges(:staff).update!(name: "Gamma")

    ordered = Badge.ordered
    assert_equal %w[Alpha Beta Gamma], ordered.pluck(:name)
  end

  test "destroying badge nullifies user associations" do
    badge = badges(:founder)
    user = users(:david)

    assert_equal badge, user.badge

    badge.destroy

    assert_nil user.reload.badge
  end
end
