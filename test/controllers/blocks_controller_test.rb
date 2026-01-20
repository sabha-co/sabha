require "test_helper"

class BlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create blocks a user" do
    assert_difference -> { Block.count }, 1 do
      post user_blocks_url(users(:jason))
    end

    assert users(:david).blocked?(users(:jason))
    assert_redirected_to room_path(Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ]))
  end

  test "create is idempotent" do
    users(:david).block!(users(:jason))

    assert_no_difference -> { Block.count } do
      post user_blocks_url(users(:jason))
    end

    assert_redirected_to room_path(Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ]))
  end

  test "destroy unblocks a user" do
    users(:david).block!(users(:jason))

    assert_difference -> { Block.count }, -1 do
      delete user_blocks_url(users(:jason))
    end

    assert_not users(:david).blocked?(users(:jason))
    assert_redirected_to room_path(Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ]))
  end

  test "destroy when not blocked does nothing" do
    assert_no_difference -> { Block.count } do
      delete user_blocks_url(users(:jason))
    end

    assert_redirected_to room_path(Rooms::Direct.find_or_create_for([ users(:david), users(:jason) ]))
  end

  test "cannot block yourself" do
    assert_raises ActiveRecord::RecordNotFound do
      post user_blocks_url(users(:david))
    end
  end
end
