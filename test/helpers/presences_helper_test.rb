require "test_helper"

class PresencesHelperTest < ActionView::TestCase
  # The groups decide where a change is delivered, so a surface missing from all
  # of them is never broadcast, and one listed twice is sent to two audiences.
  # Every surface is either a broadcast surface (in exactly one group) or a
  # deliberately transient one; a new surface fails here until it's been sorted
  # into one or the other, so nothing is silently stranded.
  test "every surface is delivered by one group or explicitly transient" do
    grouped = PresencesHelper::SURFACE_GROUPS.values.flatten
    classified = grouped + PresencesHelper::TRANSIENT_SURFACES

    assert_equal PresencesHelper::DOT_SURFACES.keys.sort, classified.sort
    assert_equal classified.uniq, classified, "a surface both broadcast and transient is contradictory"
  end

  test "an unknown group is refused rather than silently empty" do
    assert_raises(KeyError) { presence_surfaces(:everywhere) }
  end
end
