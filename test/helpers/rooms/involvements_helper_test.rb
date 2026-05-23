require "test_helper"

class Rooms::InvolvementsHelperTest < ActionView::TestCase
  include Rooms::InvolvementsHelper

  # Shared room cycling tests (3-state: mentions -> everything -> nothing -> mentions)
  test "shared room full cycle" do
    room = rooms(:hq)

    involvement = "mentions"
    involvement = next_involvement_for(room, involvement: involvement)
    assert_equal "everything", involvement

    involvement = next_involvement_for(room, involvement: involvement)
    assert_equal "nothing", involvement

    involvement = next_involvement_for(room, involvement: involvement)
    assert_equal "mentions", involvement
  end

  # Direct room cycling tests (2-state: everything -> nothing -> everything)
  test "direct room full cycle" do
    room = rooms(:david_and_jason)

    involvement = "everything"
    involvement = next_involvement_for(room, involvement: involvement)
    assert_equal "nothing", involvement

    involvement = next_involvement_for(room, involvement: involvement)
    assert_equal "everything", involvement
  end

  # Edge cases - invisible is not in the cycle, so it defaults to first + 1
  test "shared room with invisible involvement cycles to everything" do
    room = rooms(:hq)
    # invisible is not in the cycle array, index returns nil, (nil || 0) + 1 = 1
    # order[1] = "everything"
    assert_equal "everything", next_involvement_for(room, involvement: "invisible")
  end

  test "direct room with invisible involvement cycles to nothing" do
    room = rooms(:david_and_jason)
    # invisible is not in the cycle array, index returns nil, (nil || 0) + 1 = 1
    # DIRECT_INVOLVEMENT_ORDER[1] = "nothing"
    assert_equal "nothing", next_involvement_for(room, involvement: "invisible")
  end

  # Open vs Closed room behavior (both use shared cycling)
  test "open room uses shared involvement order" do
    room = rooms(:pets) # Open room
    assert_equal "everything", next_involvement_for(room, involvement: "mentions")
    assert_equal "nothing", next_involvement_for(room, involvement: "everything")
  end
end
