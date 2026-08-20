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
    badge = Badge.create!(name: "  crew  ", color: Badge::COLORS.first)
    assert_equal "CREW", badge.name
  end

  test "name must be unique, case-insensitively" do
    Badge.create!(name: "Crew", color: Badge::COLORS.first)

    duplicate = Badge.new(name: "crew", color: Badge::COLORS.second)
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "color must be one of the palette hues" do
    badge = Badge.new(name: "Test", color: "#123456")
    assert_not badge.valid?
    assert badge.errors[:color].any?

    badge.color = Badge::COLORS.first
    assert badge.valid?
  end

  test "defaults to the default palette colour" do
    assert_equal Badge::DEFAULT_COLOR, Badge.new.color
  end

  test "nearest_palette_color snaps an off-palette hex to the closest hue" do
    assert_equal "#8257E0", Badge.nearest_palette_color("#8055DD")
    assert_equal Badge::DEFAULT_COLOR, Badge.nearest_palette_color(nil)
    assert_equal Badge::DEFAULT_COLOR, Badge.nearest_palette_color("not-a-hex")
  end

  test "ordered scope sorts by definition order" do
    first = Badge.create!(name: "Alpha", color: Badge::COLORS.first)
    second = Badge.create!(name: "Beta", color: Badge::COLORS.second)

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
