require "test_helper"

class Channels::InvolvementsHelperTest < ActionView::TestCase
  include Channels::InvolvementsHelper

  # Shared channel cycling tests (3-state: mentions -> everything -> nothing -> mentions)
  test "shared channel full cycle" do
    channel = channels(:hq)

    involvement = "mentions"
    involvement = next_involvement_for(channel, involvement: involvement)
    assert_equal "everything", involvement

    involvement = next_involvement_for(channel, involvement: involvement)
    assert_equal "nothing", involvement

    involvement = next_involvement_for(channel, involvement: involvement)
    assert_equal "mentions", involvement
  end

  # Direct channel cycling tests (2-state: everything -> nothing -> everything)
  test "direct channel full cycle" do
    channel = channels(:david_and_jason)

    involvement = "everything"
    involvement = next_involvement_for(channel, involvement: involvement)
    assert_equal "nothing", involvement

    involvement = next_involvement_for(channel, involvement: involvement)
    assert_equal "everything", involvement
  end

  # Edge cases - invisible is not in the cycle, so it defaults to first + 1
  test "shared channel with invisible involvement cycles to everything" do
    channel = channels(:hq)
    # invisible is not in the cycle array, index returns nil, (nil || 0) + 1 = 1
    # order[1] = "everything"
    assert_equal "everything", next_involvement_for(channel, involvement: "invisible")
  end

  test "direct channel with invisible involvement cycles to nothing" do
    channel = channels(:david_and_jason)
    # invisible is not in the cycle array, index returns nil, (nil || 0) + 1 = 1
    # DIRECT_INVOLVEMENT_ORDER[1] = "nothing"
    assert_equal "nothing", next_involvement_for(channel, involvement: "invisible")
  end

  # Open vs Closed channel behavior (both use shared cycling)
  test "open channel uses shared involvement order" do
    channel = channels(:pets) # Open channel
    assert_equal "everything", next_involvement_for(channel, involvement: "mentions")
    assert_equal "nothing", next_involvement_for(channel, involvement: "everything")
  end
end
