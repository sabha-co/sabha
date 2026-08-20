require "test_helper"

class BadgeTest < ActiveSupport::TestCase
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

  test "name is trimmed and upper-cased on save" do
    badge = Badge.create!(name: "  crew  ", color: "#8257E0")
    assert_equal "CREW", badge.name
  end

  test "name must be unique, case-insensitively" do
    Badge.create!(name: "Crew", color: "#8257E0")

    duplicate = Badge.new(name: "crew", color: "#4F52D9")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "color must be a valid hex" do
    badge = Badge.new(name: "Test", color: "red")
    assert_not badge.valid?
    assert badge.errors[:color].any?

    badge.color = "#123456"
    assert badge.valid?
  end

  test "defaults to the default colour" do
    assert_equal Badge::DEFAULT_COLOR, Badge.new.color
  end

  test "ordered scope sorts by definition order" do
    first = Badge.create!(name: "Alpha", color: "#8257E0")
    second = Badge.create!(name: "Beta", color: "#4F52D9")

    ordered = Badge.ordered.to_a
    assert_operator ordered.index(first), :<, ordered.index(second)
  end

  test "destroying badge nullifies user associations" do
    badge = badges(:founder)
    user = users(:david)

    assert_equal badge, user.badge

    badge.destroy

    assert_nil user.reload.badge
  end
end
