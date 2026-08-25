require "test_helper"

class PresencesHelperTest < ActionView::TestCase
  # The groups decide where a change is delivered, so a surface missing from all
  # of them is never broadcast, and one listed twice is sent to two audiences.
  # Adding a ninth surface should fail here until it's been given an audience.
  test "every surface belongs to exactly one delivery group" do
    grouped = PresencesHelper::SURFACE_GROUPS.values.flatten

    assert_equal PresencesHelper::DOT_SURFACES.keys.sort, grouped.sort
    assert_equal grouped.uniq, grouped, "a surface listed in two groups is delivered twice"
  end

  test "an unknown group is refused rather than silently empty" do
    assert_raises(KeyError) { presence_surfaces(:everywhere) }
  end
end
