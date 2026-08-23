require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "record stores the normalized query, not the raw punctuation" do
    users(:david).searches.record("hover-craft!")

    assert users(:david).searches.global.exists?(query: "hover craft")
    assert_not users(:david).searches.global.exists?(query: "hover-craft!")
  end

  test "record de-duplicates punctuation variants that normalize to the same search" do
    assert_difference -> { users(:david).searches.count }, 1 do
      users(:david).searches.record("hover-craft!")
      users(:david).searches.record("hover craft ")
    end
  end
end
