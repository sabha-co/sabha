require "test_helper"

class Accounts::Bots::AvatarShufflesControllerTest < ActionDispatch::IntegrationTest
  test "create shuffles the bot's avatar seed and redirects to edit" do
    sign_in :david

    assert_changes -> { users(:bender).reload.avatar_seed } do
      post account_bot_avatar_shuffle_url(users(:bender))
    end
    assert_redirected_to edit_account_bot_url(users(:bender))
  end

  test "non-admin cannot shuffle" do
    sign_in :jz

    assert_no_changes -> { users(:bender).reload.avatar_seed } do
      post account_bot_avatar_shuffle_url(users(:bender))
    end
    assert_response :forbidden
  end
end
