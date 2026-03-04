require "test_helper"

class BlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create blocks a user and posts system message" do
    assert_difference -> { Block.count }, 1 do
      post user_block_url(users(:jason))
    end

    assert users(:david).blocked?(users(:jason))

    room = rooms(:david_and_jason)
    assert room.messages.exists?(event: "user_blocked"), "Should post blocked system message"
    assert_redirected_to root_path
  end

  test "create is idempotent and does not post duplicate system messages" do
    users(:david).block!(users(:jason))

    room = rooms(:david_and_jason)
    message_count_before = room.messages.where(event: "user_blocked").count

    assert_no_difference -> { Block.count } do
      post user_block_url(users(:jason))
    end

    assert_equal message_count_before, room.messages.where(event: "user_blocked").count
    assert_redirected_to root_path
  end

  test "destroy unblocks a user and posts system message" do
    users(:david).block!(users(:jason))

    assert_difference -> { Block.count }, -1 do
      delete user_block_url(users(:jason))
    end

    assert_not users(:david).blocked?(users(:jason))

    room = rooms(:david_and_jason)
    assert room.messages.exists?(event: "user_unblocked"), "Should post unblocked system message"
    assert_redirected_to root_path
  end

  test "destroy when not blocked does nothing" do
    assert_no_difference -> { Block.count } do
      delete user_block_url(users(:jason))
    end

    assert_redirected_to root_path
  end

  test "cannot block yourself" do
    assert_raises ActiveRecord::RecordNotFound do
      post user_block_url(users(:david))
    end
  end

  test "create redirects to return_to path when provided" do
    post user_block_url(users(:jason)), params: { return_to: "/some/path" }

    assert_redirected_to "/some/path"
  end

  test "destroy redirects to return_to path when provided" do
    users(:david).block!(users(:jason))

    delete user_block_url(users(:jason)), params: { return_to: "/some/path" }

    assert_redirected_to "/some/path"
  end
end
