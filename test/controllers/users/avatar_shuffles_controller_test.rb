require "test_helper"

class Users::AvatarShufflesControllerTest < ActionDispatch::IntegrationTest
  test "create shuffles the current user's avatar seed and redirects to profile" do
    sign_in :david

    assert_changes -> { users(:david).reload.avatar_seed } do
      post user_avatar_shuffle_url
    end
    assert_redirected_to user_profile_url
  end

  test "create requires authentication" do
    assert_no_changes -> { users(:david).reload.avatar_seed } do
      post user_avatar_shuffle_url
    end
    assert_redirected_to new_session_url
  end
end
