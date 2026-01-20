require "test_helper"

class BlockTest < ActiveSupport::TestCase
  test "valid block between two different users" do
    block = Block.new(blocker: users(:david), blocked: users(:jason))
    assert block.valid?
  end

  test "cannot block self" do
    block = Block.new(blocker: users(:david), blocked: users(:david))
    assert_not block.valid?
    assert_includes block.errors[:blocked_id], "can't be the same as blocker"
  end

  test "cannot create duplicate block" do
    Block.create!(blocker: users(:david), blocked: users(:jason))
    duplicate = Block.new(blocker: users(:david), blocked: users(:jason))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:blocked_id], "has already been taken"
  end

  test "same users can block each other (bidirectional)" do
    block1 = Block.create!(blocker: users(:david), blocked: users(:jason))
    block2 = Block.new(blocker: users(:jason), blocked: users(:david))

    assert block2.valid?
  end
end
