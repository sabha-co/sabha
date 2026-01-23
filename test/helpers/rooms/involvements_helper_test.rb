require "test_helper"

class Rooms::InvolvementsHelperTest < ActionView::TestCase
  include Rooms::InvolvementsHelper

  # Shared room cycling tests (3-state: mentions -> everything -> nothing -> mentions)
  test "shared room cycles from mentions to everything" do
    room = rooms(:hq)
    assert_equal "everything", next_involvement_for(room, involvement: "mentions")
  end

  test "shared room cycles from everything to nothing" do
    room = rooms(:hq)
    assert_equal "nothing", next_involvement_for(room, involvement: "everything")
  end

  test "shared room cycles from nothing to mentions" do
    room = rooms(:hq)
    assert_equal "mentions", next_involvement_for(room, involvement: "nothing")
  end

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
  test "direct room cycles from everything to nothing" do
    room = rooms(:david_and_jason)
    assert_equal "nothing", next_involvement_for(room, involvement: "everything")
  end

  test "direct room cycles from nothing to everything" do
    room = rooms(:david_and_jason)
    assert_equal "everything", next_involvement_for(room, involvement: "nothing")
  end

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

  test "direct room with mentions involvement cycles to nothing" do
    room = rooms(:david_and_jason)
    # mentions is not in DIRECT_INVOLVEMENT_ORDER, defaults to index 1
    assert_equal "nothing", next_involvement_for(room, involvement: "mentions")
  end

  # Open vs Closed room behavior (both use shared cycling)
  test "open room uses shared involvement order" do
    room = rooms(:pets) # Open room
    assert_equal "everything", next_involvement_for(room, involvement: "mentions")
    assert_equal "nothing", next_involvement_for(room, involvement: "everything")
  end

  test "closed room uses shared involvement order" do
    room = rooms(:watercooler) # Closed room
    assert_equal "everything", next_involvement_for(room, involvement: "mentions")
    assert_equal "nothing", next_involvement_for(room, involvement: "everything")
  end

  # Humanize labels
  test "humanize involvement labels are correct" do
    assert_equal "Room in All Rooms", Rooms::InvolvementsHelper::HUMANIZE_INVOLVEMENT["mentions"]
    assert_equal "Room in My Rooms", Rooms::InvolvementsHelper::HUMANIZE_INVOLVEMENT["everything"]
    assert_equal "Notifications muted", Rooms::InvolvementsHelper::HUMANIZE_INVOLVEMENT["nothing"]
    assert_equal "Room hidden from sidebar", Rooms::InvolvementsHelper::HUMANIZE_INVOLVEMENT["invisible"]
  end
end
